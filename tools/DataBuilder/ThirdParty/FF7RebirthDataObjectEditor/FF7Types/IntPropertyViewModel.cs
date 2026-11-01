using FF7R2.DataObject.Properties;

namespace FF7RebirthDataObjectEditor.FF7Types;

public class IntPropertyViewModel(PropertyValue propertyValue) : APropertyViewModel<int>(propertyValue)
{
	protected override bool TryParse(string input, out int result) => int.TryParse(input, out result);
}