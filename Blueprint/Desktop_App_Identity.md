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
2. **Keep the window `Icon` on the 256px brand PNG** (`logoPath`). WPF's `BitmapImage` picks only the
   *smallest* frame of a multi-size `.ico`, which would make the title-bar/taskbar window icon a soft
   upscaled 16px; the 256px PNG down-samples sharply to whatever each surface needs. (The multi-size
   `.ico` is for the Desktop / Start Menu *shortcut*, not the WPF window.)
3. **Regenerate `giok.ico` as a proper multi-size icon** (16/24/32/48/64/128/256) from the SAME
   official `giok-logo.png` artwork - not a new brand mark, just full Windows size coverage. The
   generator (`theme/assets/Build-GiokIcon.ps1`) is committed and reproduces the committed `.ico`
   byte-for-byte, so the artifact is never hand-edited.
4. **Hide the console defensively in-script**, but ONLY when the console belongs exclusively to GIOK.
   `dashboard.ps1` requires **both**: (a) this process is the console's sole client
   (`GetConsoleProcessList` == 1), so no parent shell is sharing it, and (b) `dashboard.ps1` is on
   this process's own command line (`[Environment]::GetCommandLineArgs()`), so it is a process that
   exists to run GIOK rather than an interactive shell the user typed `.\dashboard.ps1` into. Both
   signals are needed: the `.vbs` launcher and a user's own terminal are *both* sole-client (count 1),
   and only the command line separates them. Measured behaviour:

   | Launch path | sole client | started for GIOK | console |
   |---|---|---|---|
   | `launch-tony.vbs` (production) | yes | yes | hidden -> stays silent |
   | `powershell -File dashboard.ps1` (stray, fresh console) | yes | yes | hidden -> no flash |
   | `launch-tony.bat` (debug, shares `cmd.exe`) | no (2) | yes | **left visible** |
   | `.\dashboard.ps1` typed in a live terminal | yes | **no** | **left visible** |

   Interactive mode only - never during `-Screenshot` headless rendering.
5. **Reuse the existing `launch-tony.vbs`** (windowless wrapper that runs PowerShell hidden). It is
   already the exact "lightweight wrapper" this sprint calls for - text only, no binary. This is the
   real silent-launch guarantee; the in-script console hide (4) is only a defensive backstop.
6. **`Install-GiokShortcuts.ps1`** (new, committed) creates a **Desktop** and **Start Menu** shortcut
   named **GIOK**, targeting the `.vbs` launcher via `wscript.exe`, with `IconLocation = giok.ico`,
   the correct working directory, and the description "GIOK Executive Operating System". See
   **Taskbar pinning** below for how pin identity works (and its one documented limitation).

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

**Stable AUMID:** `GIOK.ExecutiveOS` (Company.Product form). GIOK sets this **in-process** with
`SetCurrentProcessExplicitAppUserModelID`, which is what the taskbar and Alt+Tab key off - so the
running window carries GIOK's own identity regardless of how it was launched.

## Taskbar pinning (and its one documented limitation)

**Pin the Desktop or Start Menu shortcut - never the running window.**
- Right-click the **GIOK** shortcut -> **Pin to taskbar**: that pin always relaunches GIOK correctly
  (`wscript.exe` -> `launch-tony.vbs`) with the GIOK icon and label.
- Do **not** right-click the *running* GIOK window's taskbar button and pin it. GIOK is hosted by
  `powershell.exe`, so a pin made from the live window resolves to bare `powershell.exe` and later
  opens an empty console instead of GIOK. `Install-GiokShortcuts.ps1` prints this guidance, and it is
  repeated in the script header.

**Limitation - the pinned shortcut and the live window may not visually merge into one taskbar
button.** Merging requires the *same* AUMID on both the process (done, in-process) and the `.lnk`
(`System.AppUserModel.ID`). The only way to stamp that id onto a `.lnk` from this text-only stack is a
COM PropertyStore call (`SHGetPropertyStoreFromParsingName` + `IPropertyStore`) that must be
JIT-compiled at install time via `Add-Type`. That compile is **intermittently blocked by real-time AV**
on this class of machine (observed both failing and succeeding across runs) - so it cannot be relied
on, and shipping code whose result silently varies per machine is worse than not shipping it. The
earlier best-effort stamp was therefore **removed** (rather than left as unreliable dead code). The
approaches that *would* guarantee a merged pin - a compiled launcher `.exe`, or an MSIX / sparse
package that declares the AUMID in a manifest - are deliberately **out of scope** for this sprint (no
compiled binary, no packaging, no fighting Windows). Net effect: the pinned shortcut launches
correctly and shows the right icon; only the cosmetic merge with the live window is unavailable.

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
- `tony-alpha/dashboard/dashboard.ps1` - set in-process AUMID; window icon from the 256px PNG;
  console hide guarded by `GetConsoleProcessList` (sole-owner + off-screen only).
- `tony-alpha/dashboard/theme/assets/giok.ico` - regenerated multi-size from `giok-logo.png`.
- `tony-alpha/dashboard/theme/assets/Build-GiokIcon.ps1` - new; committed generator that rebuilds
  `giok.ico` from `giok-logo.png` (reproduces the committed `.ico` byte-for-byte).
- `tony-alpha/dashboard/Install-GiokShortcuts.ps1` - new; creates Desktop + Start Menu shortcuts and
  prints pin guidance. (No AUMID `.lnk` stamp - see Taskbar pinning above.)
- Docs: this file; Project Status; Product Roadmap. (CTO Handoff only if a permanent packaging
  decision is made - none is; this stays a text-wrapper approach.)

## Preserved / not touched
Business logic, Life OS, Executive Context, Workforce, providers, storage, the async background
worker, startup performance, read-only provider behavior, and the 11 local runtime-data files. No new
persistent application data. `task_b9ec97bb` untouched.

## Verification (and what needs a human/GUI)
Programmatically verified here: the `.ico` is multi-size and valid (7 frames) and the committed
generator reproduces it byte-for-byte; `dashboard.ps1` parses and still launches + renders (headless);
the in-process AUMID sets and reads back as `GIOK.ExecutiveOS`; the console-hide guard was measured on
all four real launch paths (see the table above - `.vbs` stays silent, a stray `-File` launch is
hidden, `.bat` and a live terminal are **left visible**); the
shortcut install script creates `.lnk`s with the correct target, working dir, icon path, and
description (inspected via the Shell API); app closes with no orphan processes; startup timing is
unchanged. Requires a human on an interactive desktop: the actual **taskbar icon**, **Alt+Tab
visual**, **Start Menu icon**, and **no console flash** - reported as "verify on the desktop" with the
mechanism that produces them.

## Post-CTO-review refinements
Two non-blocking findings from the independent CTO review were addressed (no architecture change):
1. **Console hide is now conditional** on `GetConsoleProcessList` **plus** an own-command-line check,
   so it only ever hides a console that is both exclusively ours and created to run GIOK. It no longer
   steals a live terminal (`.\dashboard.ps1` typed at a prompt) or `launch-tony.bat`'s debug console.
   Previously it hid unconditionally. Note the count alone is insufficient - a user's terminal and the
   `.vbs` launcher are both sole-client - which is why the command-line signal is also required.
2. **The unreliable `.lnk` AUMID stamp was removed** (AV-intermittent `Add-Type` compile), replaced by
   documented **pin-the-shortcut** guidance and the merge limitation above. The installer header/param
   mismatch (`-Scope` was documented but never a parameter) was fixed, and the icon build is now a
   committed, reproducible script.

## Related
- [10_Design_System.md](10_Design_System.md) - brand/theme layer. THEME.md documents the assets.
