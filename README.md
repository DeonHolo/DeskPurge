# DeskPurge

PowerShell tool primarily used to uninstall games and save disk space: it resolves a Windows shortcut (.lnk), safely finds the real install folder, confirms with a size preview, and deletes the folder and the shortcut. Logs actions to `DeskPurge_Log.txt`.

## How It Works

When you click on a game shortcut, it often points to an `.exe` buried deep inside nested folders (e.g., `D:\Games\MyGame\bin\x64\release\game.exe`). The problem: we want to delete the entire `MyGame` folder, not just the `.exe`.

DeskPurge's solution:
1. Resolves the shortcut to find the real `.exe` location
2. Walks **up** the parent folders one level at a time
3. Stops when it hits a **protected folder** (your "stop boundary")
4. Deletes the folder right before that boundary

**Example:** If your shortcut points to `D:\Games\CoolGame\bin\game.exe` and you've set `D:\Games` as a protected folder, DeskPurge will walk up from `game.exe` → `bin` → `CoolGame` → **STOP** (because the next parent is `D:\Games`, which is protected). It then deletes `CoolGame` and the shortcut.

**Why protected folders?** Without them, the script could walk all the way up to `C:\` or `D:\` and delete your entire drive. Protected folders act as safety boundaries to prevent catastrophic deletions.

## Installation

1) Download the repo (or these files):
- `DeskPurge.ps1`
- `Install-ContextMenu.ps1` and `Uninstall-ContextMenu.ps1`
- `DeskPurge_ProtectedFolders.txt` (or start from `DeskPurge_ProtectedFolders.template.txt`)

2) Place the files in the same directory (anywhere you prefer).

3) Configure protected folders (strongly recommended):
- Copy `DeskPurge_ProtectedFolders.template.txt` to `DeskPurge_ProtectedFolders.txt` if you do not already have one.
- Open `DeskPurge_ProtectedFolders.txt` and add any root folders that must never be deleted (one path per line). For the intended use, it’s typically sufficient to add your main game library folder (for example `D:\Games`).

4) Context Menu (Shift+Right‑Click on .lnk):
- Install the context menu verb so DeskPurge appears when you hold Shift and right‑click a `.lnk`:
  ```powershell
  PowerShell -ExecutionPolicy Bypass -File .\Install-ContextMenu.ps1
  ```
- After install: hold Shift + Right‑Click a game shortcut (.lnk) → choose “DeskPurge - Uninstall”.
- To remove the verb later, run:
  ```powershell
  PowerShell -ExecutionPolicy Bypass -File .\Uninstall-ContextMenu.ps1
  ```

## Notes
- The installer targets your local `DeskPurge.ps1` and runs it with a hidden window using:
  `powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "...\DeskPurge.ps1" "%1"`
- If you move `DeskPurge.ps1` later, re‑run `Install-ContextMenu.ps1` so the registry points to the new path.

## Safety

- DeskPurge includes built‑in protections for system/user folders and supports a user list via `DeskPurge_ProtectedFolders.txt`.
- The script confirms the target folder and shows an estimated size before deleting.
- You control the “stop boundaries” by listing your main library roots in `DeskPurge_ProtectedFolders.txt`.

## Important Disclaimers

- **WARNING:** If you do **NOT** configure `DeskPurge_ProtectedFolders.txt` correctly, you can delete entire libraries. Review and update it before use.
- This tool does the same thing by right‑clicking a shortcut → Open file location → delete the containing folder and remove the shortcut. It only automates that repetitive flow to save time.
- This is a personal PowerShell script I published for my own use to clean a cluttered desktop with many game shortcuts (🏴‍☠️Yo ho ho and a bottle of rum!). It serves a niche purpose and is not recommended for general use. It does not uninstall via game launchers or remove registry keys, save data stored elsewhere, or other system traces; it is simply a folder/shortcut remover to reclaim disk space. Provided as‑is, with no warranty. Use at your own risk.

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+
