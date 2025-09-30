# DeskPurge

PowerShell tool that resolves a Windows shortcut (.lnk), safely finds the real install folder, confirms with a size preview, and deletes the folder and the shortcut. Logs actions to `DeskPurge_Log.txt`.

## Quick Start

1) Download the repo (or the two files you need):
- `DeskPurge.ps1`
- `DeskPurge_ProtectedFolders.txt` (or start from `DeskPurge_ProtectedFolders.template.txt`)

2) Place both files in the same directory (anywhere you prefer).

3) Configure protected folders (strongly recommended):
- Copy `DeskPurge_ProtectedFolders.template.txt` to `DeskPurge_ProtectedFolders.txt` if you do not already have one.
- Open `DeskPurge_ProtectedFolders.txt` and add any root folders that must never be deleted (one path per line). Examples: your game library roots, cloud folders, external drives you don’t want touched.

4) Run from PowerShell (manual run):
```powershell
PowerShell -ExecutionPolicy Bypass -File .\DeskPurge.ps1 -LinkPathFromContextMenu "C:\Path\To\Game Shortcut.lnk"
```

5) Optional: Add to Windows “Send to” menu (simple integration):
- Create a shortcut to `powershell.exe`.
- Set Target to something like:
  ```
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Path\To\DeskPurge.ps1" -LinkPathFromContextMenu "%1"
  ```
- Place that shortcut in `%APPDATA%\Microsoft\Windows\SendTo`.
- Now right‑click any `.lnk` file → Send to → your DeskPurge shortcut.

## Safety

- DeskPurge includes built‑in protections for system/user folders and supports a user list via `DeskPurge_ProtectedFolders.txt`.
- The script confirms the target folder and shows an estimated size before deleting.
- You control the “stop boundaries” by listing your main library roots in `DeskPurge_ProtectedFolders.txt`.

## Important Disclaimers

- If you do NOT configure `DeskPurge_ProtectedFolders.txt` correctly, you can delete entire libraries. Review and update it before use.
- This is a personal PowerShell script published for my own use. It is provided as‑is, with no warranty. Use at your own risk.

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+

## Protected Folders (Template)
Copy `DeskPurge_ProtectedFolders.template.txt` to `DeskPurge_ProtectedFolders.txt` and edit as needed. The existing local file is never modified by the script.
