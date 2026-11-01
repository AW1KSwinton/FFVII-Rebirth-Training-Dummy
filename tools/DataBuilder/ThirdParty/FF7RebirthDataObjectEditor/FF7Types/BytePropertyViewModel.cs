using FF7R2.DataObject.Properties;

namespace FF7RebirthDataObjectEditor.FF7Types;

public class BytePropertyViewModel(PropertyValue propertyValue) : APropertyViewModel<byte>(propertyValue)
{
	protected override bool TryParse(string input, out byte result) => byte.TryParse(input, out result);
}