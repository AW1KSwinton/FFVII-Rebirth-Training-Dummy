using FF7R2.DataObject.Properties;

namespace FF7RebirthDataObjectEditor.FF7Types;

public class UIntPropertyViewModel(PropertyValue propertyValue) : APropertyViewModel<uint>(propertyValue)
{
	protected override bool TryParse(string input, out uint result) => uint.TryParse(input, out result);
}