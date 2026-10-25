Set fileSystem = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
scriptPath = fileSystem.BuildPath(fileSystem.GetParentFolderName(WScript.ScriptFullName), "BlackOverlay.ps1")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File """ & scriptPath & """", 0, False