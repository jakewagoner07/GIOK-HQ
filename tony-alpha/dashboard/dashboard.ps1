# =====================================================================
# dashboard.ps1  —  Tony Alpha desktop entry point
# ---------------------------------------------------------------------
# Modes:
#   (default)             open the hub in a desktop window (Dashboard view)
#   -View <name>          which view to start on (Dashboard/Agents/Issues/...)
#   -Screenshot <png>     render the current view to PNG and exit (headless)
#
# This file only wires the layers together: no business logic (core/)
# and no visual construction (ui/). Requires Windows PowerShell 5.1 (STA)
# + .NET WPF (built into Windows).
# =====================================================================

param(
    [string]   $Screenshot,
    [int]      $Width  = 1180,
    [int]      $Height = 820,
    [datetime] $Now,
    [string]   $View = 'Morning Experience'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Silent launcher = no console, so surface any startup failure in a dialog.
try {

. (Join-Path $PSScriptRoot 'core\tony-core.ps1')
. (Join-Path $PSScriptRoot 'core\action-items.ps1')
. (Join-Path $PSScriptRoot 'core\capture.ps1')
. (Join-Path $PSScriptRoot 'core\tony-memory.ps1')
. (Join-Path $PSScriptRoot 'core\morning-brief.ps1')
. (Join-Path $PSScriptRoot 'core\morning-experience.ps1')
. (Join-Path $PSScriptRoot 'core\command-bar.ps1')
. (Join-Path $PSScriptRoot 'theme\theme-loader.ps1')
. (Join-Path $PSScriptRoot 'ui\tony-ui.ps1')

$theme = Get-Theme
$startNow = if ($PSBoundParameters.ContainsKey('Now')) { $Now } else { Get-Date }
$shell = New-TonyShell -InitialView $View -Now $startNow -Theme $theme
$rootVisual = $shell.Root

if ($Screenshot) {
    $rootVisual.Width = $Width; $rootVisual.Height = $Height
    $size = New-Object Windows.Size($Width, $Height)
    $rootVisual.Measure($size)
    $rootVisual.Arrange((New-Object Windows.Rect(0, 0, $Width, $Height)))
    $rootVisual.UpdateLayout()

    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($Width, $Height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($rootVisual)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb)) | Out-Null

    $outPath = if ([System.IO.Path]::IsPathRooted($Screenshot)) { $Screenshot } else { Join-Path (Get-Location).Path $Screenshot }
    $outPath = [System.IO.Path]::GetFullPath($outPath)
    $dir = Split-Path $outPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $fs = [System.IO.File]::Create($outPath); $encoder.Save($fs); $fs.Dispose()
    Write-Host "Screenshot saved: $outPath"
    return
}

# ---- interactive desktop window ----
$window = New-Object Windows.Window
$window.Title = $theme.companyName        # taskbar/title bar shows the brand (e.g. "GIOK")
$window.Width = $Width; $window.Height = $Height
$window.MinWidth = 980; $window.MinHeight = 680
$window.WindowStartupLocation = 'CenterScreen'
$window.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($theme.colors.background)))
if ($theme.logoPath -and (Test-Path $theme.logoPath)) {
    $ico = New-Object Windows.Media.Imaging.BitmapImage
    $ico.BeginInit(); $ico.CacheOption = 'OnLoad'; $ico.UriSource = New-Object Uri($theme.logoPath); $ico.EndInit()
    $window.Icon = $ico
}
$window.Content = $rootVisual

# live clock in the top bar
$clock = $shell.ClockBlock
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    $n = Get-Date
    $clock.Text = ('{0}  -  {1}' -f $n.ToString('ddd, MMM d'), $n.ToString('h:mm tt'))
})
$timer.Start()

# Ctrl+K opens/focuses the global "Ask Tony" command bar
$window.Add_PreviewKeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::K -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        Focus-CommandBar
        $e.Handled = $true
    }
})

$null = $window.ShowDialog()

}
catch {
    $msg = "GIOK could not start.`n`n" + $_.Exception.Message
    # In headless screenshot mode a modal dialog would block forever - print instead.
    if ($Screenshot) { Write-Host "ERROR: $msg"; Write-Host $_.ScriptStackTrace; exit 1 }
    [System.Windows.MessageBox]::Show($msg, 'GIOK', 'OK', 'Error') | Out-Null
    exit 1
}
