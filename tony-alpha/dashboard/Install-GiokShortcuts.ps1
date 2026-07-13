# =====================================================================
# Install-GiokShortcuts.ps1  -  create GIOK Desktop + Start Menu shortcuts
# ---------------------------------------------------------------------
# One-time helper. Creates (or refreshes) a Desktop shortcut and a Start Menu
# shortcut named "GIOK" that launch the app SILENTLY (via launch-tony.vbs, which
# runs PowerShell hidden - no console window) with the GIOK icon and the app's
# stable AppUserModelID so the taskbar / Start pin group as GIOK, not PowerShell.
#
# It never touches app logic, storage, or runtime data. Re-runnable (idempotent):
# it overwrites the two GIOK shortcuts. Remove them by deleting the .lnk files.
#
#   -Scope User    (default) current user's Desktop + Start Menu
#   -TargetDir     override where the shortcuts are written (for testing)
# =====================================================================

param(
    [string]$TargetDir,        # if set, write BOTH shortcuts here instead of Desktop/Start Menu (test)
    [string]$Aumid = 'GIOK.ExecutiveOS'
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$vbs = Join-Path $here 'launch-tony.vbs'
$ico = Join-Path $here 'theme\assets\giok.ico'
$wscript = Join-Path $env:WINDIR 'System32\wscript.exe'

if (-not (Test-Path $vbs)) { throw "Silent launcher not found: $vbs" }
if (-not (Test-Path $ico)) { throw "Icon not found: $ico" }

# ---- AppUserModelID stamping via the Windows property store (best-effort) ----
# Setting System.AppUserModel.ID on the .lnk makes a pinned shortcut share one
# taskbar button with the running window (which sets the same id in-process).
# This needs a small C# type; if that cannot compile (some AV real-time scanners
# transiently lock the temp assembly), we STILL create the shortcut and simply
# skip the stamp - the app sets the same AUMID in-process at runtime regardless.
$script:AumidHelperReady = $false
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace GiokLnk {
  [StructLayout(LayoutKind.Sequential, Pack=4)]
  public struct PropertyKey { public Guid fmtid; public uint pid; }
  [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IPropertyStore {
    void GetCount(out uint c);
    void GetAt(uint i, out PropertyKey k);
    void GetValue(ref PropertyKey k, out object pv);
    void SetValue(ref PropertyKey k, ref object pv);
    void Commit();
  }
  public static class Aumid {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
    static extern int SHGetPropertyStoreFromParsingName(string path, IntPtr zero, int flags, ref Guid iid, out IPropertyStore store);
    public static void Set(string lnkPath, string appId) {
      Guid iid = new Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"); // IPropertyStore
      IPropertyStore store;
      int hr = SHGetPropertyStoreFromParsingName(lnkPath, IntPtr.Zero, 0x00000002 /*GPS_READWRITE*/, ref iid, out store);
      if (hr != 0 || store == null) throw new Exception("store hr=" + hr);
      PropertyKey key = new PropertyKey();
      key.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"); // PKEY_AppUserModel_ID
      key.pid = 5;
      object val = appId;
      store.SetValue(ref key, ref val);
      store.Commit();
      Marshal.ReleaseComObject(store);
    }
  }
}
'@
    $script:AumidHelperReady = $true
}
catch { Write-Host ("  note: AppUserModelID helper could not compile ({0}); shortcuts will still be created, and the app sets the AUMID in-process at runtime." -f $_.Exception.GetType().Name) }

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
    $aumidOk = $false
    if ($script:AumidHelperReady) { try { [GiokLnk.Aumid]::Set($LnkPath, $Aumid); $aumidOk = $true } catch { } }
    return [pscustomobject]@{ path = $LnkPath; aumidStamped = $aumidOk }
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

$results = foreach ($t in $targets) { New-GiokShortcut -LnkPath $t }
foreach ($r in $results) {
    Write-Host ("Created shortcut: {0}  (AppUserModelID stamped: {1})" -f $r.path, $r.aumidStamped)
}
Write-Host ("Icon: {0}" -f $ico)
Write-Host ("Launcher: {0} (silent, no console)" -f $vbs)
Write-Host ("AppUserModelID: {0}" -f $Aumid)
