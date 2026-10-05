using System.Globalization;
using System.Windows.Data;

namespace NextAITranslator;

// Keep both text rows usable when zoomed controls exceed the viewport height.
public sealed class ContentMinimumHeightConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture)
    {
        // Two 80px text rows, plus the control bar's 20px and footer's 12px margins.
        var height = 192.0;
        foreach (var value in values)
            if (value is double actualHeight && double.IsFinite(actualHeight))
                height += actualHeight;
        return height;
    }

    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
