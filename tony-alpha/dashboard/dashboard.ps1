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
. (Join-Path $PSScriptRoot 'core\morning-brief.ps1')
. (Join-Path $PSScriptRoot 'core\morning-experience.ps1')
. (Join-Path $PSScriptRoot 'core\identity.ps1')
. (Join-Path $PSScriptRoot 'core\life-os.ps1')
. (Join-Path $PSScriptRoot 'core\executive-inbox.ps1')
. (Join-Path $PSScriptRoot 'core\action-engine.ps1')
. (Join-Path $PSScriptRoot 'core\conversational-capture.ps1')
. (Join-Path $PSScriptRoot 'core\end-of-day-audit.ps1')
. (Join-Path $PSScriptRoot 'core\first-conversation.ps1')
. (Join-Path $PSScriptRoot 'core\reasoning-layer.ps1')
. (Join-Path $PSScriptRoot 'core\understanding-engine.ps1')
. (Join-Path $PSScriptRoot 'core\reasoning-local.ps1')
. (Join-Path $PSScriptRoot 'core\reasoning-consent.ps1')
. (Join-Path $PSScriptRoot 'core\reasoning-claude.ps1')
. (Join-Path $PSScriptRoot 'core\daily-plan.ps1')
. (Join-Path $PSScriptRoot 'core\home-layout.ps1')
. (Join-Path $PSScriptRoot 'core\command-bar.ps1')
. (Join-Path $PSScriptRoot 'core\tony-provider-contract.ps1')
. (Join-Path $PSScriptRoot 'core\tony-decision-framework.ps1')
. (Join-Path $PSScriptRoot 'core\tony-brain.ps1')
. (Join-Path $PSScriptRoot 'core\tony-conversation.ps1')
. (Join-Path $PSScriptRoot 'core\tony-observations.ps1')
. (Join-Path $PSScriptRoot 'core\memory-manager.ps1')
. (Join-Path $PSScriptRoot 'core\executive-cache.ps1')
. (Join-Path $PSScriptRoot 'core\async-run.ps1')
. (Join-Path $PSScriptRoot 'core\live-providers.ps1')
. (Join-Path $PSScriptRoot 'core\google-oauth.ps1')
. (Join-Path $PSScriptRoot 'core\email-intelligence.ps1')
. (Join-Path $PSScriptRoot 'core\communications.ps1')
. (Join-Path $PSScriptRoot 'core\crm-intelligence.ps1')
. (Join-Path $PSScriptRoot 'core\executive-context.ps1')
. (Join-Path $PSScriptRoot 'core\executive-priority.ps1')
. (Join-Path $PSScriptRoot 'core\executive-timeline.ps1')
. (Join-Path $PSScriptRoot 'core\executive-briefing.ps1')
. (Join-Path $PSScriptRoot 'core\document-intelligence.ps1')
. (Join-Path $PSScriptRoot 'core\workforce-engine.ps1')
. (Join-Path $PSScriptRoot 'core\workforce-specialists.ps1')
. (Join-Path $PSScriptRoot 'core\workforce-proposals.ps1')
. (Join-Path $PSScriptRoot 'core\executive-management.ps1')
. (Join-Path $PSScriptRoot 'providers\claude-provider.ps1')
. (Join-Path $PSScriptRoot 'providers\weather-provider.ps1')
. (Join-Path $PSScriptRoot 'providers\google-calendar-provider.ps1')
. (Join-Path $PSScriptRoot 'providers\gmail-provider.ps1')
. (Join-Path $PSScriptRoot 'providers\yahoo-provider.ps1')
. (Join-Path $PSScriptRoot 'providers\gohighlevel-provider.ps1')
. (Join-Path $PSScriptRoot 'theme\theme-loader.ps1')
. (Join-Path $PSScriptRoot 'ui\tony-ui.ps1')
. (Join-Path $PSScriptRoot 'ui\life-workspaces.ps1')

$theme = Get-Theme
# Headless screenshot mode has no dispatcher message loop, so views that defer
# heavy work to a background tick (e.g. the Home Executive Briefing) must build
# synchronously to render. Interactive launches defer for a responsive first paint.
$script:HeadlessRender = [bool]$Screenshot
# Where the background worker runspace loads its modules from (Epic 9).
if (Get-Command Set-AsyncDashboardRoot -ErrorAction SilentlyContinue) { Set-AsyncDashboardRoot $PSScriptRoot }
# Where the bounded reasoning worker (Epic 13 Claude driver) loads its modules from.
if (Get-Command Set-ReasoningDashboardRoot -ErrorAction SilentlyContinue) { Set-ReasoningDashboardRoot $PSScriptRoot }
# Executive Action Engine (Epic 15): recover any execution interrupted mid-flight by a
# previous crash. Each non-terminal record is re-verified against its owner store and
# resolved to succeeded/failed - never re-run blindly. Best-effort; never blocks launch.
if (Get-Command Restore-ActionEngine -ErrorAction SilentlyContinue) { try { [void](Restore-ActionEngine) } catch { } }
$startNow = if ($PSBoundParameters.ContainsKey('Now')) { $Now } else { Get-Date }
# First Conversation replaces onboarding: until it's completed, it is the landing view.
$startView = if ($PSBoundParameters.ContainsKey('View')) { $View }
             elseif (-not (Get-ConversationState).completed) { 'First Conversation' }
             else { $View }
$shell = New-TonyShell -InitialView $startView -Now $startNow -Theme $theme
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

# ---- native Windows app identity (interactive launches only; -Screenshot returned above) ----
# A stable AppUserModelID makes Windows group the taskbar / Alt+Tab entry under GIOK
# instead of the PowerShell host process.
#
# Console handling: the production launcher (launch-tony.vbs) already starts PowerShell with
# -WindowStyle Hidden, so no console is ever shown on the normal path. This is a defensive
# backstop for launches that would otherwise strand a console on screen, and it must never
# take away a console the user owns. A console belongs exclusively to GIOK only when BOTH:
#   (a) this process is its sole client (GetConsoleProcessList == 1) - so no parent shell
#       is sharing it, and
#   (b) this process exists purely to run dashboard.ps1 (the script is on our own command
#       line) - so it is not an interactive shell the user typed .\dashboard.ps1 into.
# Which gives:
#   * launch-tony.vbs -> sole owner + started for GIOK -> stays hidden (silent).
#   * a stray "powershell -File dashboard.ps1" (fresh visible console) -> hidden, no flash.
#   * launch-tony.bat -> console shared with cmd.exe (count >= 2) -> left VISIBLE for debugging.
#   * .\dashboard.ps1 typed into an existing terminal -> dashboard.ps1 is not on that shell's
#     command line -> left VISIBLE, so the user never loses their own terminal.
# Best-effort: if the P/Invoke is unavailable the app still runs.
try {
    Add-Type -Namespace GIOK -Name Shell -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode, PreserveSig=false)]
public static extern void SetCurrentProcessExplicitAppUserModelID(string AppID);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
public static extern uint GetConsoleProcessList(uint[] lpdwProcessList, uint dwProcessCount);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
    [GIOK.Shell]::SetCurrentProcessExplicitAppUserModelID('GIOK.ExecutiveOS')

    $consoleWnd = [GIOK.Shell]::GetConsoleWindow()
    if ($consoleWnd -ne [System.IntPtr]::Zero) {
        $attached = New-Object 'uint32[]' 4
        $soleClient = ([GIOK.Shell]::GetConsoleProcessList($attached, 4) -eq 1)
        $startedForGiok = @([Environment]::GetCommandLineArgs() |
            Where-Object { $_ -like '*dashboard.ps1*' }).Count -gt 0
        if ($soleClient -and $startedForGiok) {
            [void][GIOK.Shell]::ShowWindow($consoleWnd, 0)  # 0 = SW_HIDE
        }
    }
}
catch { }

# ---- interactive desktop window ----
$window = New-Object Windows.Window
$window.Title = $theme.companyName        # taskbar/title bar shows the brand (e.g. "GIOK")
$window.Width = $Width; $window.Height = $Height
$window.MinWidth = 980; $window.MinHeight = 680
$window.WindowStartupLocation = 'CenterScreen'
$window.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($theme.colors.background)))
# Window icon (title bar + taskbar window icon): the 256px brand PNG, which WPF
# down-samples sharply to whatever size each surface needs. (The multi-size .ico
# serves the Desktop / Start Menu shortcut; a WPF BitmapImage would pick only the
# smallest .ico frame here, so the PNG stays the better window-icon source.)
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

# Ctrl+K opens the dedicated "Talk with Tony" conversation window (primary AI
# interaction). The quick-command bar remains for typed commands.
$window.Add_PreviewKeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::K -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        Open-TonyConversation | Out-Null
        $e.Handled = $true
    }
})

# Tear down background runspaces on close so no orphan runspaces or file locks leak;
# clear the scan-local reject-suppression set (in-memory only) on close.
$window.Add_Closed({
    if (Get-Command Stop-AsyncWorkers -ErrorAction SilentlyContinue) { Stop-AsyncWorkers }
    if (Get-Command Stop-ReasoningWorkers -ErrorAction SilentlyContinue) { Stop-ReasoningWorkers }
    if (Get-Command Reset-InboxScanRejected -ErrorAction SilentlyContinue) { Reset-InboxScanRejected }
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
