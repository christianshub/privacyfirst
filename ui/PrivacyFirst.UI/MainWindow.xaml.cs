using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Security.Principal;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;

namespace PrivacyFirst.UI
{
    public partial class MainWindow : Window
    {
        private readonly ObservableCollection<OperationItem> _operations;
        private bool _isRunning = false;

        public MainWindow()
        {
            InitializeComponent();

            // Check if running as administrator
            CheckAdminPrivileges();

            // Initialize operations list
            _operations = new ObservableCollection<OperationItem>
            {
                new OperationItem { Id = 1, Name = "Create Restore Point", IsEnabled = true, SupportsRestore = false, ActionButtonVisibility = Visibility.Collapsed },
                new OperationItem { Id = 2, Name = "Uninstall Game", IsEnabled = false, SupportsRestore = false, HasCustomAction = true, CustomActionText = "Launch", ActionButtonText = "Launch" },
                new OperationItem { Id = 3, Name = "Registry HWIDs", IsEnabled = true },
                new OperationItem { Id = 4, Name = "VPN Setup", IsEnabled = false, SupportsRestore = false, HasCustomAction = true, CustomActionText = "Setup", ActionButtonText = "Setup" },
                new OperationItem { Id = 5, Name = "Disk IDs", IsEnabled = false },
                new OperationItem { Id = 6, Name = "Hardware IDs (SMBIOS)", IsEnabled = false },
                new OperationItem { Id = 7, Name = "MAC Address", IsEnabled = false },
                new OperationItem { Id = 8, Name = "Monitor HWID", IsEnabled = false },
                new OperationItem { Id = 9, Name = "Peripheral Serials", IsEnabled = false },
                new OperationItem { Id = 10, Name = "Privacy Cleaner", IsEnabled = false, SupportsRestore = false, ActionButtonVisibility = Visibility.Collapsed }
            };

            OperationsList.ItemsSource = _operations;

            // Set up callbacks from C++ DLL
            SetupCallbacks();

            // Refresh all operation values
            RefreshAllOperations();

            // Log startup
            Log("PrivacyFirst initialized. DLL version: " + GetDllVersion());
        }

        private void CheckAdminPrivileges()
        {
            bool isAdmin = new WindowsPrincipal(WindowsIdentity.GetCurrent())
                .IsInRole(WindowsBuiltInRole.Administrator);

            if (isAdmin)
            {
                AdminStatus.Text = "Admin Mode: ✓";
                AdminStatus.Foreground = System.Windows.Media.Brushes.LightGreen;
            }
            else
            {
                AdminStatus.Text = "Admin Mode: ✗";
                AdminStatus.Foreground = System.Windows.Media.Brushes.Red;
                Log("WARNING: Not running as Administrator. Some operations may fail!");
            }
        }

        private void SetupCallbacks()
        {
            try
            {
                NativeMethods.SetProgressCallback(OnProgress);
                NativeMethods.SetLogCallback(OnLog);
            }
            catch (Exception ex)
            {
                Log($"Error setting up callbacks: {ex.Message}");
            }
        }

        private void OnProgress(string message, int progress)
        {
            Dispatcher.Invoke(() =>
            {
                StatusText.Text = $"{message} ({progress}%)";
            });
        }

        private void OnLog(string message, int level)
        {
            Dispatcher.Invoke(() =>
            {
                string prefix = level switch
                {
                    0 => "[INFO]",
                    1 => "[WARN]",
                    2 => "[ERROR]",
                    _ => "[DEBUG]"
                };
                Log($"{prefix} {message}");
            });
        }

        private void Log(string message)
        {
            string timestamp = DateTime.Now.ToString("HH:mm:ss");
            OutputLog.Text += $"[{timestamp}] {message}\n";
        }

        private void RefreshAllOperations()
        {
            foreach (var op in _operations.Where(o => o.SupportsRestore))
            {
                op.RefreshValues();
            }
        }

        private string GetDllVersion()
        {
            try
            {
                var versionPtr = NativeMethods.GetDllVersion();
                return NativeMethods.PtrToStringAndFree(versionPtr) ?? "Unknown";
            }
            catch
            {
                return "Error";
            }
        }

        // Button Handlers
        private void EnableAll_Click(object sender, RoutedEventArgs e)
        {
            foreach (var op in _operations)
            {
                op.IsEnabled = true;
            }
            Log("All operations enabled");
        }

        private void DisableAll_Click(object sender, RoutedEventArgs e)
        {
            foreach (var op in _operations)
            {
                op.IsEnabled = false;
            }
            Log("All operations disabled");
        }

        private async void RunEnabled_Click(object sender, RoutedEventArgs e)
        {
            if (_isRunning)
            {
                Log("Operations already running!");
                return;
            }

            var enabledOps = _operations.Where(o => o.IsEnabled).ToList();

            if (!enabledOps.Any())
            {
                Log("No operations enabled!");
                MessageBox.Show("Please enable at least one operation.", "No Operations", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            _isRunning = true;
            StatusText.Text = "Running operations...";

            try
            {
                int successCount = 0;
                int failureCount = 0;

                Log($"Executing {enabledOps.Count} enabled operations...");

                foreach (var op in enabledOps)
                {
                    Log($"Executing: {op.Name}...");

                    await Task.Run(() =>
                    {
                        int result = NativeMethods.Execute(op.Id, null);

                        Dispatcher.Invoke(() =>
                        {
                            if (result == 0) // STATUS_SUCCESS
                            {
                                Log($"✓ {op.Name} completed successfully");
                                successCount++;
                            }
                            else if (result == 2) // STATUS_NOT_IMPLEMENTED
                            {
                                Log($"⚠ {op.Name} is not yet implemented");
                                failureCount++;
                            }
                            else
                            {
                                var errorPtr = NativeMethods.GetLastErrorMessage();
                                var error = NativeMethods.PtrToStringAndFree(errorPtr);
                                Log($"✗ {op.Name} failed: {error}");
                                failureCount++;
                            }

                            // Refresh values after execution
                            op.RefreshValues();
                        });
                    });
                }

                Log($"\nExecution complete: {successCount} succeeded, {failureCount} failed");
                StatusText.Text = $"Complete: {successCount} succeeded, {failureCount} failed";

                if (failureCount == 0)
                {
                    MessageBox.Show($"All {successCount} operations completed successfully!", "Success",
                        MessageBoxButton.OK, MessageBoxImage.Information);
                }
            }
            catch (Exception ex)
            {
                Log($"Error during execution: {ex.Message}");
                MessageBox.Show($"Error: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
            finally
            {
                _isRunning = false;
                StatusText.Text = "Ready";
            }
        }

        private async void ActionButton_Click(object sender, RoutedEventArgs e)
        {
            if (sender is not System.Windows.Controls.Button button || button.Tag is not OperationItem op)
                return;

            if (op.HasCustomAction)
            {
                // Custom actions (Launch, Setup, etc.)
                Log($"Executing custom action for {op.Name}...");
                await Task.Run(() =>
                {
                    int result = NativeMethods.Execute(op.Id, null);
                    Dispatcher.Invoke(() =>
                    {
                        if (result == 0)
                        {
                            Log($"✓ {op.Name} action completed");
                        }
                        else
                        {
                            Log($"✗ {op.Name} action failed");
                        }
                    });
                });
            }
            else
            {
                // Restore operation
                Log($"Restoring {op.Name}...");
                await Task.Run(() =>
                {
                    int result = NativeMethods.Restore(op.Id);
                    Dispatcher.Invoke(() =>
                    {
                        if (result == 0)
                        {
                            Log($"✓ {op.Name} restored successfully");
                            op.RefreshValues();
                        }
                        else if (result == 3) // STATUS_NO_BACKUP
                        {
                            Log($"⚠ No backup found for {op.Name}");
                            MessageBox.Show($"No backup found for {op.Name}", "No Backup",
                                MessageBoxButton.OK, MessageBoxImage.Warning);
                        }
                        else
                        {
                            Log($"✗ Failed to restore {op.Name}");
                        }
                    });
                });
            }
        }

        private void Settings_Click(object sender, RoutedEventArgs e)
        {
            Log("Settings clicked (not yet implemented)");
            MessageBox.Show("Settings dialog coming soon!", "Settings", MessageBoxButton.OK, MessageBoxImage.Information);
        }

        // Window Control Handlers
        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ClickCount == 2)
            {
                WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
            }
            else
            {
                DragMove();
            }
        }

        private void MinimizeButton_Click(object sender, RoutedEventArgs e)
        {
            WindowState = WindowState.Minimized;
        }

        private void MaximizeButton_Click(object sender, RoutedEventArgs e)
        {
            WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e)
        {
            Close();
        }
    }
}
