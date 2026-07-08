# =====================================================================
# dashboard.ps1  —  Tony Alpha desktop entry point
# ---------------------------------------------------------------------
# Two modes:
#   (default)          open the dashboard in a desktop window
#   -Screenshot <png>  render the exact same UI to a PNG and exit (headless)
#
# This file wires the layers together; it contains no business logic
# (that is in core/) and no visual construction (that is in ui/).
# Requires: Windows PowerShell 5.1 (STA) + .NET WPF (built into Windows).
# =====================================================================

param(
    [string]   $Screenshot,
    [int]      $Width  = 1180,
    [int]      $Height = 820,
    [datetime] $Now                       # optional: override the clock (used for screenshots)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Because the app launches with no console (silent launcher), any startup
# failure would otherwise be invisible. Surface it in a native dialog.
try {

. (Join-Path $PSScriptRoot 'core\tony-core.ps1')
. (Join-Path $PSScriptRoot 'ui\tony-ui.ps1')

$model = if ($PSBoundParameters.ContainsKey('Now')) { Get-TonyModel -Now $Now } else { Get-TonyModel }
$built = New-TonyDashboardVisual -Model $model
$rootVisual = $built.Root

if ($Screenshot) {
    # ---- headless render to PNG (used for review screenshots) ----
    $rootVisual.Width  = $Width
    $rootVisual.Height = $Height
    $size = New-Object Windows.Size($Width, $Height)
    $rootVisual.Measure($size)
    $rootVisual.Arrange((New-Object Windows.Rect(0, 0, $Width, $Height)))
    $rootVisual.UpdateLayout()

    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($Width, $Height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($rootVisual)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb)) | Out-Null

    $outPath = if ([System.IO.Path]::IsPathRooted($Screenshot)) { $Screenshot }
               else { Join-Path (Get-Location).Path $Screenshot }
    $outPath = [System.IO.Path]::GetFullPath($outPath)
    $dir = Split-Path $outPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $fs = [System.IO.File]::Create($outPath)
    $encoder.Save($fs)
    $fs.Dispose()
    Write-Host "Screenshot saved: $outPath"
    return
}

# ---- interactive desktop window ----
$window = New-Object Windows.Window
$window.Title = 'Tony Alpha - Command Center'
$window.Width = $Width
$window.Height = $Height
$window.MinWidth = 980
$window.MinHeight = 680
$window.WindowStartupLocation = 'CenterScreen'
$window.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#F3F5F9')))
$window.Content = $rootVisual

# live clock
$timeBlock = $built.TimeBlock
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    $now = Get-Date
    $timeBlock.Text = ('{0}   -   {1}' -f $now.ToString('dddd, MMMM d, yyyy'), $now.ToString('h:mm:ss tt'))
})
$timer.Start()

$null = $window.ShowDialog()

}
catch {
    $msg = "Tony Alpha could not start.`n`n" + $_.Exception.Message
    [System.Windows.MessageBox]::Show($msg, 'Tony Alpha', 'OK', 'Error') | Out-Null
    exit 1
}
