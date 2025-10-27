using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;

namespace PrivacyFirst.UI
{
    public class OperationItem : INotifyPropertyChanged
    {
        private bool _isEnabled;
        private string _currentValue = "-";
        private string _originalValue = "-";

        public int Id { get; set; }
        public string Name { get; set; } = "";

        public bool IsEnabled
        {
            get => _isEnabled;
            set
            {
                if (_isEnabled != value)
                {
                    _isEnabled = value;
                    OnPropertyChanged();
                }
            }
        }

        public string CurrentValue
        {
            get => _currentValue;
            set
            {
                if (_currentValue != value)
                {
                    _currentValue = value;
                    OnPropertyChanged();
                }
            }
        }

        public string OriginalValue
        {
            get => _originalValue;
            set
            {
                if (_originalValue != value)
                {
                    _originalValue = value;
                    OnPropertyChanged();
                }
            }
        }

        public string ActionButtonText { get; set; } = "Restore";
        public Visibility ActionButtonVisibility { get; set; } = Visibility.Visible;

        public bool SupportsRestore { get; set; } = true;
        public bool HasCustomAction { get; set; } = false;
        public string CustomActionText { get; set; } = "";

        public event PropertyChangedEventHandler? PropertyChanged;

        protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }

        public void RefreshValues()
        {
            if (SupportsRestore)
            {
                var currentPtr = NativeMethods.GetCurrent(Id);
                var originalPtr = NativeMethods.GetOriginal(Id);

                CurrentValue = NativeMethods.PtrToStringAndFree(currentPtr) ?? "-";
                OriginalValue = NativeMethods.PtrToStringAndFree(originalPtr) ?? "-";
            }
        }
    }
}
