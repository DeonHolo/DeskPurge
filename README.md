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

**Why protected folders?** Protected folders are essential safety boundaries. Without them, DeskPurge could accidentally walk up the folder tree and delete much more than intended, potentially your entire game library (there is a confirmation dialog of course, but nothing can be done if you confirm, as the deletion type is permanent). By setting protected folders (like your game library root), you ensure the script only deletes the intended game folder and nothing beyond your chosen stop points.

## Who It's For

- Users with games installed outside of launchers or across multiple drives
- People with deep, nested shortcut targets (bin/x64/release, etc.)
- Anyone wanting a fast, safe way to reclaim disk space from old installs
- Power users who like context‑menu workflows; beginner‑safe with confirmations

## Installation

1) Clone the repository
```bash
git clone https://github.com/DeonHolo/DeskPurge.git
```
2) Configure protected folders (REQUIRED):
- Open `DeskPurge_ProtectedFolders.txt` and update it with your actual game library root folders
- Example: If your games are in `E:\Media\Games`, add that path to prevent deleting the entire library
- The file includes common example library locations - remove or modify as needed (no real harm in keeping them there)

3) Context Menu (Shift+Right‑Click on .lnk):
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

- 🔒 **Built-in protections:** Root drives (`C:\`, `D:\`, etc.), `C:\Windows`, `C:\Program Files`, User Profile, and Desktop are automatically protected
- 📁 **User-defined boundaries:** Add your game library folders to `DeskPurge_ProtectedFolders.txt` to prevent deleting entire libraries
- ✅ **Confirmation dialog:** Shows the target folder and estimated size before deleting
- 🚫 **Process check:** Ensures the game isn't running before deletion

## Important Disclaimers & Competitive Justification

### DeskPurge vs. Advanced Uninstallers (e.g., Revo)

DeskPurge is a fast, workflow‑centric tool; Revo is a deep system uninstaller. Different jobs, different tools.

| Feature   | DeskPurge                              | Revo (Hunter Mode)                         | Why it matters                                   |
| :--       | :--                                    | :--                                        | :--                                              |
| Workflow  | One‑click context‑menu action          | Drag target / multi‑step activation        | Speed: instant, low‑friction cleanup             |
| Focus     | Deletes install folder (filesystem)    | Registry + system trace removal            | Direct: maximizes immediate disk space reclaimed |
| Automation| Auto‑resolves .lnk targets to game root| Manual drag or path entry                  | Efficient for bulk shortcut cleanups             |

- **Core limitation:** DeskPurge deletes the install folder and the shortcut only. It does not call launchers or scrub registry/system traces—use Revo for full cleanups.
- **WARNING:** If you do NOT configure `DeskPurge_ProtectedFolders.txt` correctly, you can delete entire game libraries. Review and add your library paths before use.
- Provided as‑is, with no warranty. Use at your own risk.

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+

## License

MIT License - see [LICENSE](LICENSE) for details.
