using System.ComponentModel;

namespace FF7RebirthDataObjectEditor;

public interface IPropertyViewModel : INotifyPropertyChanged
{
	ICollection<IPropertyViewModel> Children { get; }
	string Name { get; }
	string Value { get; set; }
}