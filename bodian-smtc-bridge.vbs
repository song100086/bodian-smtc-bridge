' Launches the Bodian -> SMTC bridge with NO visible window.
'
' The autostart shortcut points here instead of the .cmd, because a .cmd always
' leaves (or flashes) a console window. Run-WindowStyle 0 = fully hidden.
'
' Double-clicking this file starts the bridge silently.
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
here = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & here & "\bodian-smtc-bridge.ps1""", 0, False
