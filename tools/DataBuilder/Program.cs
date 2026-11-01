// Training Dummy data builder.
//
// Adds new rows to FF7 Rebirth DataObject tables by cloning an existing row
// and overriding named properties, as described by a JSON spec. Existing rows
// are never changed. Every output is reloaded and checked before the command
// reports success.
//
//   TrainingDummy.DataBuilder build  <spec.json> <vanilla-root> <output-root>
//   TrainingDummy.DataBuilder export <input.uasset> <output.csv>
//
// <vanilla-root> and <output-root> are content roots containing
// End/Content/<asset path>, the layout UnrealReZen packs from.
using System.Reflection;
using System.Text;
using System.Text.Json;
using CUE4Parse.UE4.Objects.UObject;
using FF7R2.DataObject;
using FF7R2.DataObject.Properties;
using FF7RebirthDataObjectEditor;
using FF7RebirthDataObjectEditor.FF7Types;
using TrainingDummy.DataBuilder;

return Builder.Run(args);

internal static class Builder
{
    public static int Run(string[] args)
    {
        try
        {
            if (args.Length == 4 && args[0] == "build") return Build(args[1], args[2], args[3]);
            if (args.Length == 3 && args[0] == "export") { Export(args[1], args[2]); return 0; }
            Console.Error.WriteLine("usage: build <spec.json> <vanilla-root> <output-root> | export <input.uasset> <output.csv>");
            return 2;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(Environment.GetEnvironmentVariable("TD_DEBUG") == "1" ? ex.ToString() : $"error: {ex.Message}");
            return 1;
        }
    }

    static int Build(string specPath, string vanillaRoot, string outputRoot)
    {
        var spec = JsonSerializer.Deserialize<Spec>(File.ReadAllText(specPath),
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true, ReadCommentHandling = JsonCommentHandling.Skip })
            ?? throw new InvalidDataException("spec is empty");
        foreach (var table in spec.Tables)
        {
            var input = Path.Combine(vanillaRoot, "End", "Content", table.Asset);
            var output = Path.Combine(outputRoot, "End", "Content", table.Asset);
            if (Path.GetFullPath(input).Equals(Path.GetFullPath(output), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException($"{table.Asset}: output must not overwrite the vanilla asset");
            Directory.CreateDirectory(Path.GetDirectoryName(output));

            var asset = IoStoreAsset.Load(input);
            var originalCount = asset.innerAsset.frozenObject.DataTable.Count;
            var views = new List<RowPropertiesViewModel>();
            foreach (var row in table.Rows)
                views.Add(row.CloneFrom == null ? Modify(asset, row) : AddClone(asset, row));
            FixFNames(asset, views);
            RowMap.Save(asset, output);

            Verify(input, output, originalCount, table.Rows);
            var addedCount = table.Rows.Count(r => r.CloneFrom != null);
            Console.WriteLine($"{table.Asset}: {originalCount} vanilla rows + {addedCount} new, "
                + $"{table.Rows.Count - addedCount} repurposed -> {output}");
        }
        return 0;
    }

    static RowPropertiesViewModel AddClone(IoStoreAsset asset, RowSpec row)
    {
        var frozen = asset.innerAsset.frozenObject;
        if (frozen.DataTable.Keys.Any(k => k.ToString() == row.Name))
            throw new InvalidDataException($"row {row.Name} already exists");
        var source = frozen.DataTable.FirstOrDefault(kv => kv.Key.ToString() == row.CloneFrom).Value
            ?? throw new InvalidDataException($"clone source {row.CloneFrom} not found");

        var clone = new Entry(frozen, source.properties);
        clone.propertyValues.Clear();
        foreach (var value in source.propertyValues)
            clone.propertyValues.Add(Copy(frozen, value));

        var view = new RowPropertiesViewModel(clone);
        Apply(view, row);
        RowMap.Append(frozen, asset.AddFName(row.Name), clone);
        return view;
    }

    // Repurposes an existing row (no cloneFrom): some tables, EnemyTerritory
    // among them, break every simulator battle when a row is added, so the
    // mod reuses an unused vanilla row there instead.
    static RowPropertiesViewModel Modify(IoStoreAsset asset, RowSpec row)
    {
        var entry = asset.innerAsset.frozenObject.DataTable.FirstOrDefault(kv => kv.Key.ToString() == row.Name).Value
            ?? throw new InvalidDataException($"row {row.Name} to repurpose not found");
        var view = new RowPropertiesViewModel(entry);
        Apply(view, row);
        return view;
    }

    static void Apply(RowPropertiesViewModel view, RowSpec row)
    {
        foreach (var (name, wanted) in row.Set)
        {
            var property = view.Properties.SingleOrDefault(p => p.Name == name)
                ?? throw new InvalidDataException($"{row.Name}: no property {name}");
            if (property is ArrayPropertyViewModel array)
            {
                var values = wanted.ValueKind == JsonValueKind.Array
                    ? wanted.EnumerateArray().Select(v => v.ToString()).ToList()
                    : throw new InvalidDataException($"{row.Name}.{name} is an array; give a JSON array");
                while (array.Children.Count > 0) array.RemoveAt(array.Children.Count - 1);
                for (var i = 0; i < values.Count; i++)
                    array.InsertAt(i, array.CreatePropertyValue()).Value = values[i];
            }
            else
            {
                if (wanted.ValueKind == JsonValueKind.Array)
                    throw new InvalidDataException($"{row.Name}.{name} is not an array");
                property.Value = wanted.ToString();
            }
        }
    }

    // A deep copy of a parsed value: same property descriptor, new storage.
    // An array's descriptor creates elements, so the array itself is built
    // directly and each element is copied.
    static PropertyValue Copy(FrozenObject frozen, PropertyValue source)
    {
        if (source is ArrayProperty sourceArray)
        {
            var target = new ArrayProperty(frozen, source.property);
            target.Data.Clear();
            foreach (var child in sourceArray.Data) target.Data.Add(Copy(frozen, child));
            return target;
        }
        var copy = source.property.Create();
        var data = copy.GetType().GetProperty("Data", BindingFlags.Public | BindingFlags.Instance)
            ?? throw new InvalidDataException($"{source.property.name}: value has no Data");
        data.SetValue(copy, data.GetValue(source));
        return copy;
    }

    // Names typed into new rows must exist in the package's name map; the
    // logic follows Yoraiz0r's editor (Utils.FixFNames), restricted to the
    // rows this tool created.
    static void FixFNames(IoStoreAsset asset, IEnumerable<RowPropertiesViewModel> views)
    {
        var names = asset.innerAsset.frozenObject.NameToOffsetLookup.Keys.ToList();
        foreach (var prop in views.SelectMany(v => Flatten(v.Properties)).OfType<NamePropertyViewModel>())
        {
            var wanted = prop.UserText;
            if (wanted == null) continue;
            var match = names.Cast<FName?>().FirstOrDefault(n => n.Value.ToString() == wanted);
            if (match == null)
            {
                match = asset.AddFName(wanted);
                names.Add(match.Value);
            }
            prop.Data = match;
        }
    }

    static IEnumerable<IPropertyViewModel> Flatten(IEnumerable<IPropertyViewModel> roots)
    {
        foreach (var p in roots)
        {
            yield return p;
            foreach (var c in Flatten(p.Children)) yield return c;
        }
    }

    static void Verify(string input, string output, int originalCount, List<RowSpec> rows)
    {
        var asset = IoStoreAsset.Load(output);
        var table = asset.innerAsset.frozenObject.DataTable;
        var expectedCount = originalCount + rows.Count(r => r.CloneFrom != null);
        if (table.Count != expectedCount)
            throw new InvalidDataException($"{output}: expected {expectedCount} rows, found {table.Count}");
        // Every vanilla row the spec does not repurpose must read back exactly as in the vanilla asset.
        var repurposed = rows.Where(r => r.CloneFrom == null).Select(r => r.Name).ToHashSet();
        var vanilla = IoStoreAsset.Load(input).innerAsset.frozenObject.DataTable;
        foreach (var (key, entry) in vanilla)
        {
            var written = table.FirstOrDefault(kv => kv.Key.ToString() == key.ToString()).Value
                ?? throw new InvalidDataException($"{output}: vanilla row {key} missing");
            if (!repurposed.Contains(key.ToString()) && Flat(entry) != Flat(written))
                throw new InvalidDataException($"{output}: vanilla row {key} changed");
        }
        foreach (var row in rows)
        {
            var entry = table.FirstOrDefault(kv => kv.Key.ToString() == row.Name).Value
                ?? throw new InvalidDataException($"{output}: new row {row.Name} missing after reload");
            var view = new RowPropertiesViewModel(entry);
            foreach (var (name, wanted) in row.Set)
            {
                var property = view.Properties.Single(p => p.Name == name);
                var actual = property is ArrayPropertyViewModel
                    ? string.Join("|", property.Children.Select(c => c.Value))
                    : property.Value;
                var expected = wanted.ValueKind == JsonValueKind.Array
                    ? string.Join("|", wanted.EnumerateArray().Select(v => v.ToString()))
                    : wanted.ToString();
                if (!Same(actual, expected))
                    throw new InvalidDataException($"{row.Name}.{name}: wrote '{expected}', read back '{actual}'");
            }
        }
    }

    static string Flat(Entry entry) => string.Join("\u001f", new RowPropertiesViewModel(entry).Properties.Select(p =>
        p.Name + "=" + (p is ArrayPropertyViewModel ? string.Join("|", p.Children.Select(c => c.Value)) : p.Value)));

    static bool Same(string actual, string expected)
    {
        if ((actual ?? "") == (expected ?? "")) return true;
        return double.TryParse(actual, out var a) && double.TryParse(expected, out var e) && a == e;
    }

    static void Export(string input, string output)
    {
        var asset = IoStoreAsset.Load(input);
        var sb = new StringBuilder("Index,Name,Property,Value\n");
        var index = 0;
        foreach (var (key, entry) in asset.innerAsset.frozenObject.DataTable)
        {
            foreach (var p in new RowPropertiesViewModel(entry).Properties)
            {
                var value = p is ArrayPropertyViewModel ? string.Join("|", p.Children.Select(c => c.Value)) : p.Value;
                sb.Append(index).Append(',').Append(key).Append(',').Append(p.Name).Append(",\"")
                  .Append((value ?? "").Replace("\"", "\"\"")).Append("\"\n");
            }
            index++;
        }
        File.WriteAllText(output, sb.ToString());
    }
}

internal sealed class Spec
{
    public List<TableSpec> Tables { get; set; } = [];
}

internal sealed class TableSpec
{
    // Path under End/Content, e.g. DataObject/Resident/Colosseum.uasset.
    public string Asset { get; set; }
    public List<RowSpec> Rows { get; set; } = [];
}

internal sealed class RowSpec
{
    public string Name { get; set; }
    public string CloneFrom { get; set; }
    public Dictionary<string, JsonElement> Set { get; set; } = [];
}
