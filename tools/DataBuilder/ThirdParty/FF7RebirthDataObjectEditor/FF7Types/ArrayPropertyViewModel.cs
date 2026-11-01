using System.ComponentModel;
using System.Diagnostics;
using FF7R2.DataObject.Properties;

namespace FF7RebirthDataObjectEditor.FF7Types;
public class ArrayPropertyViewModel : IPropertyViewModel
{
    private readonly List<IPropertyViewModel> _children = new();
    public ICollection<IPropertyViewModel> Children => _children;
    public event PropertyChangedEventHandler PropertyChanged;


    protected void OnPropertyChanged(string propertyName) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    public readonly ArrayProperty PropertyValue;


    public PropertyValue UnderlyingValue { get; }
    private string _arraySummary;

    public ArrayPropertyViewModel(ArrayProperty propertyValue)
    {
        UnderlyingValue = propertyValue;
        PropertyValue = propertyValue;
        PopulateChildren();
        UpdateSummary();
    }

    private void PopulateChildren()
    {
        foreach (var propertyValue in PropertyValue.Data)
        {
            var childViewModel = PropertyViewModelFactory.Create(propertyValue);
            _children.Add(childViewModel);
            
            if (childViewModel is INotifyPropertyChanged npc)
                npc.PropertyChanged += SubPropertyChanged;
        }
    }

    private void SubPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        UpdateSummary();
        OnPropertyChanged(nameof(Value));
    }

    private void UpdateSummary()
    {
        var candidate = string.Join(", ", _children.Select(x => x.Value));
        const int summaryAllowed = 50;
        if (candidate.Length > summaryAllowed)
            candidate = candidate.Substring(0, summaryAllowed - 1) + "…";
        _arraySummary = $"{_children.Count, -4} | {candidate}";
    }

    public string Name => PropertyValue.property.name.ToString();

    public string Value
    {
        get => _arraySummary;
        set { }
    }

    public IPropertyViewModel InsertAt(int index, PropertyValue newPropertyValue)
    {
        PropertyValue.Data.Insert(index, newPropertyValue);

        var newChildViewModel = PropertyViewModelFactory.Create(newPropertyValue);

        _children.Insert(index, newChildViewModel);

        if (newChildViewModel is INotifyPropertyChanged npc)
            npc.PropertyChanged += SubPropertyChanged;

        UpdateSummary();
        OnPropertyChanged(nameof(Children));
        OnPropertyChanged(nameof(Value));
        return newChildViewModel;
    }

    public void RemoveAt(int index)
    {
        if (_children[index] is INotifyPropertyChanged npc)
            npc.PropertyChanged -= SubPropertyChanged;

        PropertyValue.Data.RemoveAt(index);

        _children.RemoveAt(index);

        UpdateSummary();
        OnPropertyChanged(nameof(Children));
        OnPropertyChanged(nameof(Value));
    }
    

    public PropertyValue CreatePropertyValue()
    {
        var genericArrayProperty = PropertyValue.property;
        var instancedArrayElement = genericArrayProperty.Create();
        return instancedArrayElement;
    }
}
