using CUE4Parse.GameTypes.FF7.Assets.Objects.Properties;
using FF7R2.DataObject.Properties;

namespace FF7RebirthDataObjectEditor.FF7Types;

public static class PropertyViewModelFactory
{
	public static IPropertyViewModel Create(PropertyValue propertyValue)
	{
		if (propertyValue is ArrayProperty arrayProperty)
			return new ArrayPropertyViewModel(arrayProperty);
		
		return propertyValue.property.UnderlyingType switch
		{
			FF7propertyType.BoolProperty => new BoolPropertyViewModel(propertyValue),
			FF7propertyType.ByteProperty => new BytePropertyViewModel(propertyValue),
			FF7propertyType.Int8Property => new Int8PropertyViewModel(propertyValue),
			FF7propertyType.UInt16Property => new UInt16PropertyViewModel(propertyValue),
			FF7propertyType.Int16Property => new Int16PropertyViewModel(propertyValue),
			FF7propertyType.UIntProperty => new UIntPropertyViewModel(propertyValue),
			FF7propertyType.IntProperty => new IntPropertyViewModel(propertyValue),
			FF7propertyType.Int64Property => new Int64PropertyViewModel(propertyValue),
			FF7propertyType.FloatProperty => new FloatPropertyViewModel(propertyValue),
			FF7propertyType.StrProperty => new StringPropertyViewModel(propertyValue),
			FF7propertyType.NameProperty => new NamePropertyViewModel(propertyValue),
			_ => throw new NotSupportedException($"Unsupported property type?: {propertyValue.property.UnderlyingType}")
		};
	}
}