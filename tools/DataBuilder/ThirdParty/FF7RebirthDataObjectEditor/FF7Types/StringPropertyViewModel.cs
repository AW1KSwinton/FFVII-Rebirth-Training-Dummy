using FF7R2.DataObject.Properties;

namespace FF7RebirthDataObjectEditor.FF7Types;

public class StringPropertyViewModel(PropertyValue propertyValue) : APropertyViewModel<string>(propertyValue)
{
	protected override bool TryParse(string input, out string result)
	{
		result = input;
		return true;
	}
	
	public override string Value
	{
		get => Data?.ToString();
		set
		{
			if (!TryParse(value, out var parsed))
				return;

			if (string.IsNullOrWhiteSpace(value))
				parsed = null;
			
			Data = parsed;
		}
	}
}