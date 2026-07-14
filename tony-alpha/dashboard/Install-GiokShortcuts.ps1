# =====================================================================
# Install-GiokShortcuts.ps1  -  create GIOK Desktop + Start Menu shortcuts
# ---------------------------------------------------------------------
# One-time helper. Creates (or refreshes) a Desktop shortcut and a Start Menu
# shortcut named "GIOK" that launch the app SILENTLY (via launch-tony.vbs, which
# runs PowerShell hidden - no console window) with the GIOK icon.
#
# It never touches app logic, storage, or runtime data. Re-runnable (idempotent):
# it overwrites the two GIOK shortcuts. Remove them by deleting the .lnk files.
#
#   -TargetDir <path>   write BOTH shortcuts into this folder instead of the
#                       current user's Desktop + Start Menu (used by tests).
#
# ---------------------------------------------------------------------
# Taskbar pinning (read this):
#   PIN THE DESKTOP OR START MENU SHORTCUT, NOT THE RUNNING WINDOW.
#
#   * Right-click the "GIOK" Desktop/Start Menu icon -> Pin to taskbar. That pin
#     always relaunches GIOK correctly (wscript -> launch-tony.vbs) with the GIOK
#     icon and label.
#   * Do NOT right-click the running GIOK window's taskbar button and "Pin". The
#     app is hosted by powershell.exe, so that pin resolves to bare powershell.exe
#     and later opens an empty console instead of GIOK.
#
#   Known limitation: the pinned shortcut and the live GIOK window may show as two
#   separate taskbar buttons (they do not visually merge). GIOK sets its
#   AppUserModelID ("GIOK.ExecutiveOS") in-process so the running window has its own
#   GIOK identity for the taskbar/Alt+Tab, but the ONLY reliable way to also stamp
#   that same id onto the .lnk is a COM PropertyStore call that must be JIT-compiled
#   at install time (Add-Type). That compile is intermittently blocked by real-time
#   AV on this class of machine, so it cannot be relied on - and the alternatives
#   that would guarantee a merged pin (a compiled launcher .exe, or an MSIX/sparse
#   package) are deliberately out of scope for this text-only approach. The shortcut
#   launches correctly and shows the right icon regardless; only the cosmetic merge
#   is unavailable. See Blueprint/Desktop_App_Identity.md.
# =====================================================================

param(
    [string]$TargetDir         # if set, write BOTH shortcuts here instead of Desktop/Start Menu (test)
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$vbs = Join-Path $here 'launch-tony.vbs'
$ico = Join-Path $here 'theme\assets\giok.ico'
$wscript = Join-Path $env:WINDIR 'System32\wscript.exe'

if (-not (Test-Path $vbs)) { throw "Silent launcher not found: $vbs" }
if (-not (Test-Path $ico)) { throw "Icon not found: $ico" }

function New-GiokShortcut {
    param([string]$LnkPath)
    $dir = Split-Path -Parent $LnkPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (Test-Path $LnkPath) { Remove-Item $LnkPath -Force }
    $sh = New-Object -ComObject WScript.Shell
    $sc = $sh.CreateShortcut($LnkPath)
    $sc.TargetPath = $wscript
    $sc.Arguments = ('"{0}"' -f $vbs)      # wscript runs the .vbs windowless
    $sc.WorkingDirectory = $here
    $sc.IconLocation = ('{0},0' -f $ico)
    $sc.WindowStyle = 1
    $sc.Description = 'GIOK Executive Operating System'
    $sc.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh) | Out-Null
    return $LnkPath
}

$targets = @()
if ($TargetDir) {
    $targets += (Join-Path $TargetDir 'GIOK.lnk')
}
else {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startPrograms = [Environment]::GetFolderPath('Programs')
    $targets += (Join-Path $desktop 'GIOK.lnk')
    $targets += (Join-Path $startPrograms 'GIOK.lnk')
}

foreach ($t in $targets) {
    $p = New-GiokShortcut -LnkPath $t
    Write-Host ("Created shortcut: {0}" -f $p)
}
Write-Host ("Icon:     {0}" -f $ico)
Write-Host ("Launcher: {0} (silent, no console)" -f $vbs)
Write-Host ''
Write-Host 'To pin GIOK to the taskbar: right-click the Desktop or Start Menu "GIOK"'
Write-Host 'shortcut and choose "Pin to taskbar". Do NOT pin the running window - that'
Write-Host 'pin would resolve to powershell.exe. (See the header notes in this file.)'
