# DeskPurge

PowerShell tool that resolves a Windows shortcut (.lnk), safely finds the real install folder, confirms with a size preview, and deletes the folder and shortcut. Logs actions to DeskPurge_Log.txt.

## Usage
`powershell
# From PowerShell
.\DeskPurge.ps1 -LinkPathFromContextMenu "C:\\Path\\To\\Game.lnk"
`

## Safety

- Protects system/user folders and configurable roots via DeskPurge_ProtectedFolders.txt.
- Confirms before deletion and logs outcomes.

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+
