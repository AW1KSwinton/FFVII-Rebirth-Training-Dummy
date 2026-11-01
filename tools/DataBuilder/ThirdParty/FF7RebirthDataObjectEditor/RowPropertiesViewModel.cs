using FF7R2.DataObject;
using FF7RebirthDataObjectEditor.FF7Types;

namespace FF7RebirthDataObjectEditor;

public class RowPropertiesViewModel
{
	private readonly List<IPropertyViewModel> _properties;
	public List<IPropertyViewModel> Properties => _properties;


	public RowPropertiesViewModel(Entry entry)
	{
		_properties = new List<IPropertyViewModel>();
		foreach (var propertyValue in entry.propertyValues)
			_properties.Add(PropertyViewModelFactory.Create(propertyValue));
	}

	public RowPropertiesViewModel(IPropertyViewModel propertyViewModel)
	{
		_properties = new List<IPropertyViewModel>();
		_properties.Add(propertyViewModel);
	}
}