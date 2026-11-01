using FF7R2.DataObject.Properties;

namespace FF7RebirthDataObjectEditor.FF7Types;

public class Int16PropertyViewModel(PropertyValue propertyValue) : APropertyViewModel<short>(propertyValue)
{
	protected override bool TryParse(string input, out short result) => short.TryParse(input, out result);
}