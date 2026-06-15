# DeskPurge

PowerShell tool primarily used to uninstall games and save disk space: it resolves a Windows shortcut (.lnk), safely finds the real install folder, confirms with a size preview, and deletes the folder and the shortcut. Logs actions to `DeskPurge_Log.txt`.

DeskPurge supports both single and batch desktop workflows through one context-menu action. Select one shortcut or many shortcuts, Shift+Right-Click the final selected shortcut, choose `DeskPurge - Uninstall`, review the detected install folder(s), and confirm once.

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

1) Download the repo (or these files):
- `DeskPurge.ps1`
- `DeskPurge.Core.ps1`
- `Install-ContextMenu.ps1` and `Uninstall-ContextMenu.ps1`
- `DeskPurge_ProtectedFolders.txt`

2) Place the files in the same directory (anywhere you prefer).

3) ⚠️ Confirm protected folders (required):
- DeskPurge needs protected folders before it can delete anything. These are stop boundaries, usually the folders that directly contain your game folders.
- If `DeskPurge_ProtectedFolders.txt` is missing or has no active entries, DeskPurge opens a setup window and suggests likely library roots from the selected shortcut(s) and common existing game-library folders.
- Review the suggestions, keep only paths that directly contain game folders, and save. You can also edit `DeskPurge_ProtectedFolders.txt` manually.
- Example: If your games are in `E:\Media\Games`, use that path to prevent deleting the entire library.
- For Steam libraries, use the folder that directly contains each game folder, usually `...\steamapps\common`.

4) Context Menu (Shift+Right‑Click on .lnk):
- Install the context menu verb so DeskPurge appears when you hold Shift and right‑click a `.lnk`:
  ```powershell
  PowerShell -ExecutionPolicy Bypass -File .\Install-ContextMenu.ps1
  ```
- After install: hold Shift + Right‑Click one game shortcut (.lnk) → choose “DeskPurge - Uninstall”.
- For batch cleanup: select multiple desktop shortcuts, hold Shift + Right‑Click the final selected shortcut → choose “DeskPurge - Uninstall”. DeskPurge opens one review window for the selected shortcuts and confirms once.
- To remove the verb later, run:
  ```powershell
  PowerShell -ExecutionPolicy Bypass -File .\Uninstall-ContextMenu.ps1
  ```

## Notes
- By default, the installer expects the DeskPurge scripts in the same directory. If your script lives elsewhere, pass `-ScriptPath "C:\Path\To\DeskPurge.ps1"`.
- The installer creates `DeskPurge.Hidden.vbs` next to `DeskPurge.ps1` and points the context menu at `wscript.exe`.
  This avoids the split-second PowerShell console flash that can happen when Explorer starts `powershell.exe` directly.
- If you move the DeskPurge scripts later, re‑run `Install-ContextMenu.ps1` so the registry points to the new paths.
- Public Desktop shortcuts may require admin rights. DeskPurge detects those rows and offers a restart-as-admin path instead of silently leaving the shortcut behind.
- The old single-shortcut implementation is kept under `legacy/` for reference only; the root `DeskPurge.ps1` is the current adaptive single/batch version.

## Safety

- 🔒 **Built-in protections:** Root drives (`C:\`, `D:\`, etc.), `C:\Windows`, `C:\Program Files`, User Profile, and Desktop are automatically protected
- 📁 **Confirmed boundaries:** `DeskPurge_ProtectedFolders.txt` is required; DeskPurge can suggest likely game-library folders, but you must confirm them before deletion is allowed
- ✅ **Confirmation dialog:** Shows the target folder and estimated size before deleting
- ✅ **Multi-shortcut review:** Shows selected shortcuts in one table and only deletes checked ready rows
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
- **WARNING:** If you confirm the wrong protected folder paths, you can delete entire game libraries. Review the setup suggestions or manually added paths before use.
- Provided as‑is, with no warranty. Use at your own risk.

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+

## License

MIT License - see [LICENSE](LICENSE) for details.
