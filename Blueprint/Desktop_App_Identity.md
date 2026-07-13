# Desktop App Identity (GIOK as a Windows Application)

*Make Windows recognize GIOK as its own app - taskbar, Alt+Tab, title bar, and shortcuts - instead
of showing the PowerShell / Windows Script Host identity. No app redesign, no migration off
PowerShell/WPF, no business-logic change.*

## Exact Windows-identity root cause

GIOK runs as `powershell.exe -File dashboard.ps1` (started silently by `launch-tony.vbs`, which runs
PowerShell hidden). Windows derives a window's taskbar/Alt+Tab identity from the process's
**Application User Model ID (AUMID)**, not from the window title. GIOK never sets an explicit AUMID,
so Windows falls back to the host process's default (PowerShell / Windows Script Host) - that is why
the taskbar groups and labels it as PowerShell and Alt+Tab can show PowerShell.

Three concrete gaps:
1. **No explicit AUMID.** `dashboard.ps1` never calls `SetCurrentProcessExplicitAppUserModelID`, so
   the taskbar/Alt+Tab identity defaults to the host process (PowerShell).
2. **Window icon comes from the PNG, and the `.ico` is single-size.** The window sets `Window.Icon`
   from `logoPath` (a 256px PNG). The official `theme/assets/giok.ico` exists but has only one
   256x256 entry, so Windows down-scales it to 16-48px for the taskbar/Alt+Tab and it looks soft.
3. **No branded shortcuts.** There is no Desktop / Start Menu shortcut carrying the GIOK icon and
   AUMID; the app is launched by hand. (`launch-tony.vbs` already launches PowerShell hidden - the
   console-window problem is effectively already solved by that wrapper.)

The window **title** is already `GIOK` and `Window.Icon` is already set - so the title bar is fine;
the missing piece is process **identity** (AUMID) + a crisp multi-size icon + real shortcuts.

## Approach selected (and why): native WPF identity + existing wrapper + branded shortcuts

**Chosen - the smallest safe, fully-visible fix, no compiled binary:**
1. **Set a stable AUMID in `dashboard.ps1`** before the window is created:
   `SetCurrentProcessExplicitAppUserModelID("GIOK.ExecutiveOS")` via a tiny `shell32` P/Invoke. This
   is THE fix for taskbar grouping and Alt+Tab identity - it makes the running window GIOK's own app,
   separate from PowerShell, with zero behavior change.
2. **Point the window `Icon` at the multi-size `.ico`** (`iconPath`), falling back to `logoPath`, so
   the taskbar/Alt+Tab/title icons are crisp at every size.
3. **Regenerate `giok.ico` as a proper multi-size icon** (16/24/32/48/64/128/256) from the SAME
   official `giok-logo.png` artwork - not a new brand mark, just full Windows size coverage.
4. **Hide the console defensively in-script** (`ShowWindow(GetConsoleWindow(), SW_HIDE)`) for direct
   `.ps1`/`.bat` launches - only in interactive mode, never during `-Screenshot` headless rendering.
   The silent `.vbs` launcher already prevents any console from appearing on the normal path.
5. **Reuse the existing `launch-tony.vbs`** (windowless wrapper that runs PowerShell hidden). It is
   already the exact "lightweight wrapper" this sprint calls for - text only, no binary.
6. **`Install-GiokShortcuts.ps1`** (new, committed) creates a **Desktop** and **Start Menu** shortcut
   named **GIOK**, targeting the `.vbs` launcher via `wscript.exe`, with `IconLocation = giok.ico`,
   the correct working directory, and the **same AUMID** stamped on the shortcut
   (`System.AppUserModel.ID`) so pinning/Start identity matches the running window.

**Why not a compiled launcher `.exe` (the sprint's optional preference):** a `.exe` would add
process-level version metadata (product name / company / version PE resource) and the cleanest
no-flash launch - but none of that is user-visible (the taskbar/Alt+Tab identity is driven by the
running WPF window's AUMID, which the approach above already sets). Against it: it introduces a
**compiled binary into a source repo**, needs a build step, and - most importantly - a small `.exe`
that spawns hidden PowerShell is a **classic pattern that Bitdefender/Defender heuristics flag**
(assessed honestly below). Since a working text wrapper already exists and the visible identity is
fully solved without it, the `.exe` is **not necessary**. It is documented here as an optional future
step if process-level branding is ever wanted, and can be added behind the same AUMID/icon with no
change to the app.

**Stable AUMID:** `GIOK.ExecutiveOS` (Company.Product form; used identically by the process and the
shortcuts so Windows treats them as one app for grouping/pinning).

## Antivirus / Bitdefender assessment (honest)

Any approach that launches a WPF app through hidden PowerShell has some AV sensitivity - this is
inherent to running a `.ps1` GUI app, not to this change:
- `launch-tony.vbs` -> `powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass` is a pattern AV
  heuristics sometimes flag. It already exists and is unchanged by this sprint.
- Real-time AV may briefly scan the regenerated `giok.ico` and the new `.ps1`/shortcut on first use;
  no elevated permissions, no network, no registry writes are involved.
- A compiled launcher `.exe` (rejected) would raise this risk materially (unsigned small exe +
  hidden PowerShell spawn is a common malware signature). Avoiding it lowers AV exposure.
- The AUMID P/Invoke (`SetCurrentProcessExplicitAppUserModelID`) is a documented Shell API and is
  not AV-sensitive.
Mitigation if a machine's AV flags the launcher: the user can allow-list the GIOK folder, or launch
via `launch-tony.bat`. No code signing is attempted in this sprint.

## What changes (files/assets)
- `tony-alpha/dashboard/dashboard.ps1` - set AUMID; window icon from `.ico`; defensive console hide.
- `tony-alpha/dashboard/theme/assets/giok.ico` - regenerated multi-size from `giok-logo.png`.
- `tony-alpha/dashboard/Install-GiokShortcuts.ps1` - new; creates Desktop + Start Menu shortcuts.
- Docs: this file; Project Status; Product Roadmap. (CTO Handoff only if a permanent packaging
  decision is made - none is; this stays a text-wrapper approach.)

## Preserved / not touched
Business logic, Life OS, Executive Context, Workforce, providers, storage, the async background
worker, startup performance, read-only provider behavior, and the 11 local runtime-data files. No new
persistent application data. `task_b9ec97bb` untouched.

## Verification (and what needs a human/GUI)
Programmatically verifiable here: the `.ico` is multi-size and valid; `dashboard.ps1` parses and still
launches + renders (headless); the AUMID API resolves; the shortcut install script creates `.lnk`s
with the correct target, working dir, icon path, and AUMID (inspected via the Shell API); app closes
with no orphan processes; startup timing is unchanged. Requires a human on an interactive desktop:
the actual **taskbar icon**, **Alt+Tab visual**, **Start Menu icon**, and **no console flash** - these
are reported as "verify on the desktop" with the mechanism that produces them.

## Related
- [10_Design_System.md](10_Design_System.md) - brand/theme layer. THEME.md documents the assets.
