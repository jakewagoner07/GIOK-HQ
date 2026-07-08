' =====================================================================
'  launch-tony.vbs  -  silent launcher for Tony Alpha
' ---------------------------------------------------------------------
'  Starts the dashboard with NO PowerShell / command-prompt window.
'  wscript.exe runs windowless, and it launches PowerShell hidden
'  (WScript.Shell.Run intWindowStyle = 0), so the user only ever sees
'  the Tony Alpha application window - it feels like a native app.
'
'  This is the launcher the desktop "Tony Alpha" icon points at.
'  (launch-tony.bat is kept for terminal/debug launches that show output.)
' =====================================================================
Option Explicit

Dim shell, scriptDir, command
Set shell = CreateObject("WScript.Shell")

' folder this .vbs lives in (with trailing backslash)
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))

command = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptDir & "dashboard.ps1"""

' 0 = hidden window, False = don't wait for it to exit
shell.Run command, 0, False

Set shell = Nothing
