using CUE4Parse.UE4.Objects.UObject;
using FF7R2.DataObject.Properties;

namespace FF7RebirthDataObjectEditor.FF7Types;

public class NamePropertyViewModel(PropertyValue propertyValue) : APropertyViewModel<FName?>(propertyValue)
{
	public string UserText;
	protected override bool TryParse(string input, out FName? result)
	{
		UserText = input;
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
			{
				UserText = null;
				parsed = null;
			}
			
			Data = parsed;
		}
	}
}