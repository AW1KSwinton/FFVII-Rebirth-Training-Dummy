// Appends a row to a DataObject's frozen row map.
//
// A DataObject stores its rows as a frozen UE4 TMap<FName, int32>: a dense
// sparse array of keys {name, entry index, next key in bucket, bucket} plus a
// bucket array holding the first key of each bucket, followed by the entries
// in key order. The parser only rewrites what it read, so a new row needs a
// key, an entry and a bucket link. The bucket is UE4's FName hash,
// CityHash64(lowercase plain name) + FName number, masked to the bucket
// count; this matched every key of Colosseum, EnemyTerritory and
// BattleCharaSpec (1,010 keys) in the vanilla assets.
using System.Collections;
using System.Reflection;
using System.Text;
using CUE4Parse.UE4.Objects.UObject;
using FF7R2.DataObject;

namespace TrainingDummy.DataBuilder;

internal static class RowMap
{
    const BindingFlags Fields = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance;

    public static void Append(FrozenObject frozen, FName name, Entry entry)
    {
        var keys = Get(frozen, "keys");
        var keyData = (Key[])Get(keys, "data");
        var entries = (IList)Get(Get(frozen, "entries"), "data");
        var buckets = (List<int>)Get(Get(frozen, "indexes"), "data");
        if (keyData.Length != entries.Count || (int)Get(keys, "firstFreeIndex") != -1)
            throw new InvalidDataException("row map is not dense; refusing to append");
        CheckBuckets(keyData, buckets);

        var key = new Key(frozen) { name = name, index = entries.Count, nextIndex = -1 };
        var newKeys = keyData.Append(key).ToArray();
        entries.Add(entry);
        Set(keys, "data", newKeys);
        Set(keys, "dataMax", newKeys.Length);

        var flags = Get(keys, "allocationFlags");
        var bits = (BitArray)Get(flags, "Data");
        bits.Length = newKeys.Length;
        bits[newKeys.Length - 1] = true;
        Set(flags, "numBits", bits.Length);
        Set(flags, "maxBits", Math.Max((int)Get(flags, "maxBits"), (bits.Length + 31) / 32 * 32));

        var size = BucketCount(newKeys.Length);
        if (size != buckets.Count)
        {
            // TSet grew past its bucket count: rehash every key as UE4 would.
            buckets.Clear();
            buckets.AddRange(Enumerable.Repeat(-1, size));
            for (var i = 0; i < newKeys.Length; i++) Link(newKeys[i], i, buckets);
        }
        else Link(key, newKeys.Length - 1, buckets);
        frozen.DataTable[name] = entry;
        CheckBuckets(newKeys, buckets);
    }

    // The writer patches the key array's pointer but keeps the read pointers
    // of the arrays after it (buckets, properties, entries), which move when
    // keys are added. A first save lays everything out and records where the
    // properties landed; the pointers are set from that and the second save
    // writes the same layout with correct pointers. Property records are 12
    // bytes (FName + type) and the arrays are contiguous.
    public static void Save(IoStoreAsset asset, string output)
    {
        var frozen = asset.innerAsset.frozenObject;
        asset.Save(output, IoStoreAsset.Mode.WRITE_PARSED_DATA);
        var buckets = Get(frozen, "indexes");
        var properties = Get(frozen, "properties");
        var entries = Get(frozen, "entries");
        var propertyList = (IList)Get(properties, "data");
        var propertiesStart = (long)Get(propertyList[0], "offset");
        Point(buckets, propertiesStart - 4L * ((IList)Get(buckets, "data")).Count);
        Point(properties, propertiesStart);
        Point(entries, propertiesStart + 12L * propertyList.Count);
        asset.Save(output, IoStoreAsset.Mode.WRITE_PARSED_DATA);
        if ((long)Get(propertyList[0], "offset") != propertiesStart)
            throw new InvalidDataException("layout changed between the two saves");
    }

    static void Point(object proxy, long target)
    {
        var pointer = Get(proxy, "dataPtr");
        var packed = (ulong)Get(pointer, "packed");
        var offset = target - (long)Get(proxy, "headerPos");
        Set(pointer, "packed", (packed & 1UL) | (ulong)(offset << 1));
    }

    static void Link(Key key, int position, List<int> buckets)
    {
        key.priority = Bucket(key.name, buckets.Count);
        key.nextIndex = buckets[(int)key.priority];
        buckets[(int)key.priority] = position;
    }

    public static uint Bucket(FName name, int bucketCount)
    {
        var plain = name.PlainText.ToLowerInvariant();
        if (plain.Any(c => c > 0x7f)) throw new InvalidDataException($"non-ASCII row name {name}");
        var hash = CityHash.Hash64(Encoding.ASCII.GetBytes(plain)) + (ulong)name.Number;
        return (uint)(hash & (ulong)(bucketCount - 1));
    }

    // UE4 TSet: RoundUpToPowerOfTwo(Num / 2 + 8) buckets from 4 elements.
    static int BucketCount(int elements)
    {
        if (elements < 4) return 1;
        var wanted = elements / 2 + 8;
        var size = 1;
        while (size < wanted) size <<= 1;
        return size;
    }

    // Every key must sit in the bucket its name hashes to and be reachable
    // from that bucket's chain; this guards both the hash and the edit.
    static void CheckBuckets(Key[] keys, List<int> buckets)
    {
        for (var i = 0; i < keys.Length; i++)
        {
            var bucket = Bucket(keys[i].name, buckets.Count);
            if (keys[i].priority != bucket || keys[i].index != i)
                throw new InvalidDataException($"key {keys[i].name}: bucket {keys[i].priority}, expected {bucket}");
            var cursor = buckets[(int)bucket];
            for (var steps = 0; cursor != i; steps++)
            {
                if (cursor == -1 || steps > keys.Length)
                    throw new InvalidDataException($"key {keys[i].name} is not reachable from bucket {bucket}");
                cursor = keys[cursor].nextIndex;
            }
        }
    }

    static object Get(object owner, string field) =>
        (owner.GetType().GetField(field, Fields) ?? throw new MissingFieldException(owner.GetType().Name, field)).GetValue(owner);

    static void Set(object owner, string field, object value) =>
        (owner.GetType().GetField(field, Fields) ?? throw new MissingFieldException(owner.GetType().Name, field)).SetValue(owner, value);
}
