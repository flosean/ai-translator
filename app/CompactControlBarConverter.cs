using System.Globalization;
using System.Windows.Data;

namespace NextAITranslator;

public sealed class CompactControlBarConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => value is double width && width < 260;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
