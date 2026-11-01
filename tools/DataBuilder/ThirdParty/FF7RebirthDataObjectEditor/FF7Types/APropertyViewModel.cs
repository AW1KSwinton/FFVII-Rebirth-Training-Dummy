using System.ComponentModel;
using FF7R2.DataObject.Properties;

namespace FF7RebirthDataObjectEditor.FF7Types;

public abstract class APropertyViewModel : IPropertyViewModel
{
	public ICollection<IPropertyViewModel> Children { get; } = Array.Empty<IPropertyViewModel>();
	public PropertyValue UnderlyingValue { get; set; }
	public string Name { get; protected set; }

	public abstract string Value { get; set; }

	public event PropertyChangedEventHandler PropertyChanged;
	protected void OnPropertyChanged(string propertyName) =>
		PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}


public abstract class APropertyViewModel<T> : APropertyViewModel
{
	protected readonly Property UnderlyingProperty;
	protected readonly PropertyValue<T> _propertyValue;
	
	public APropertyViewModel(PropertyValue propertyValue)
	{
		UnderlyingProperty = propertyValue.property;
		UnderlyingValue = propertyValue;
		_propertyValue = (PropertyValue<T>)propertyValue;
		Name = UnderlyingProperty.name.ToString();
	}

	public T Data
	{
		get => _propertyValue.Data;
		set
		{
			_propertyValue.Data = value;
			OnPropertyChanged(nameof(Data));
			OnPropertyChanged(nameof(Value));
		}
	}
	
	public override string Value
	{
		get => Data?.ToString();
		set
		{
			if (TryParse(value, out var parsed))
				Data = parsed;
		}
	}

	protected abstract bool TryParse(string input, out T result);
}