using FF7R2.DataObject.Properties;

namespace FF7RebirthDataObjectEditor.FF7Types;

public class BoolPropertyViewModel(PropertyValue propertyValue) : APropertyViewModel<bool>(propertyValue)
{
	protected override bool TryParse(string input, out bool result) => bool.TryParse(input, out result);
}