using FF7R2.DataObject.Properties;

namespace FF7RebirthDataObjectEditor.FF7Types;

public class Int8PropertyViewModel(PropertyValue propertyValue) : APropertyViewModel<sbyte>(propertyValue)
{
	protected override bool TryParse(string input, out sbyte result) => sbyte.TryParse(input, out result);
}