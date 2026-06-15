# Batch Desktop Uninstall Design

## Goal

DeskPurge should support the user's current batch workflow:

1. Select multiple desktop shortcuts.
2. Shift-right-click the final selected shortcut.
3. Choose `DeskPurge - Uninstall`.
4. Review the selected shortcut or shortcuts in one DeskPurge window.
5. Confirm once.
6. Receive one completion summary.

The primary success criterion is that selecting ten shortcuts opens one batch review window, not ten independent confirmation dialogs. Selecting one shortcut should use the same entrypoint but show a focused single-item review.

## Non-Goals

- Do not add launcher registry cleanup, Windows app uninstall integration, or Revo-style trace cleanup.
- Do not delete folders without the existing protected-folder boundary checks.
- Do not introduce a compiled application dependency for the first batch version.

## Recommended Approach

Add a batch-aware PowerShell entrypoint named `DeskPurge.ps1`, and install it as the main context-menu verb named `DeskPurge - Uninstall`.

The entrypoint should accept all selected shortcut paths, resolve each shortcut, compute its proposed install folder using the same core safety helpers as the single flow, and show one WinForms review surface. The old single-shortcut implementation can remain under `legacy/` for reference, but the installer should not expose it as a context-menu item.

If Windows Explorer does not reliably pass all selected `.lnk` paths to the context-menu command on a target Windows version, the implementation should stop and report that limitation instead of building a brittle workaround. A fallback design can add a drag-and-drop or "Scan Desktop" batch window.

## UI Design

The batch UI must match the current single-version DeskPurge style:

- Dark WinForms surface.
- Same color family, typography, button styling, border treatment, and danger-button behavior used by `Show-DeskPurgeDialog`.
- Same caution-first tone.
- No marketing or instructional landing screen.

When one shortcut is selected, the review window should use a focused details layout without a checkbox selector. It should include `Open Folder` before deletion.

When multiple shortcuts are selected, the batch review window should show a table with one row per shortcut:

- Shortcut name.
- Shortcut path.
- Resolved target path.
- Proposed folder to delete.
- Estimated size.
- Boundary folder.
- Status, including the blocking reason when the row is not ready.
- Selected checkbox.

Expected statuses:

- `Ready`: folder and shortcut can be processed.
- `Needs admin`: shortcut is on the Public Desktop or another location that cannot be deleted by the current user without elevation.
- `Target missing`: the shortcut target no longer exists.
- `Blocked`: protected-folder or root-drive safety check failed.
- `Running`: target executable appears to be running from the folder.
- `Error`: shortcut could not be resolved or size could not be calculated.

Rows that are not `Ready` should default to unchecked. The user can only confirm deletion for checked rows that are ready. If any row is `Needs admin`, the window should offer a secondary `Restart as admin` action that relaunches the same batch path list with elevation and exits the non-elevated instance only after the elevated process starts.

## Data Flow

1. Explorer invokes the DeskPurge context-menu command with the selected `.lnk` paths.
2. `DeskPurge.ps1` normalizes and deduplicates the paths.
3. It loads `DeskPurge.Core.ps1` and `DeskPurge_ProtectedFolders.txt`.
4. If the protected-folder config is missing or empty:
   - Resolve selected shortcut targets.
   - Suggest protected folder candidates from known library patterns, Steam `steamapps\common`, non-system top-level install folders, and common existing library folders on mounted drives.
   - Show a setup review window and require the user to confirm which boundaries to save.
   - Stop without deleting anything if the user cancels or no safe candidates can be detected.
5. For each shortcut:
   - Validate that it is a `.lnk` file.
   - Resolve the target with `WScript.Shell`.
   - Determine the initial target parent folder.
   - Resolve the deletion target with `Resolve-DeskPurgeDeletionTarget`.
   - Apply final protected-folder checks.
   - Calculate folder size with `Get-DeskPurgeFolderSizeDisplay`.
   - Detect likely admin-needed shortcut locations, especially `C:\Users\Public\Desktop`.
6. Render the review window:
   - Single shortcut: focused single-item review.
   - Multiple shortcuts: table review with ready-row checkboxes.
7. On confirmation, process selected ready rows sequentially:
   - Recheck target and folder existence.
   - Recheck running process.
   - Delete folder first.
   - Delete shortcut second.
   - Record per-row result.
8. Show one completion summary and write one log block. For single-item completion, include an `Open Containing Folder` action when the parent folder exists.

## Error Handling

Errors should be row-level before confirmation. One bad shortcut should not block the user from deleting other ready rows.

Folder deletion failures are hard failures for that row. If a folder fails to delete, the shortcut must not be deleted.

Shortcut deletion failures after successful folder deletion should be shown in the final summary. Public Desktop shortcuts should be detected before deletion and marked `Needs admin` so this case becomes predictable rather than surprising. When the batch window is already elevated, Public Desktop rows can be classified as `Ready` if all other checks pass.

If no ready rows remain, the primary destructive button should be disabled and the window should show the blocking statuses.

## Architecture

Keep destructive filesystem operations out of `DeskPurge.Core.ps1`, matching the current testable helper boundary.

Add or extract pure helpers for batch planning where practical:

- Shortcut path normalization and deduplication.
- Shortcut resolution result modeling.
- Deletion target planning for one shortcut.
- Status classification.
- Protected-folder setup candidate detection.

The WinForms UI can live in the root `DeskPurge.ps1`. If matching the single-version style creates large copy-paste blocks, extract the shared dialog styling helpers into a dedicated GUI helper file as part of the same implementation. Do not extract unrelated behavior.

## Installer Changes

Update `Install-ContextMenu.ps1` to install one adaptive context-menu verb named `DeskPurge - Uninstall`, backed by the root `DeskPurge.ps1`. Remove any older separate `DeskPurge - Batch Uninstall` verb during installation.

The installer must write any needed hidden launcher next to the DeskPurge scripts and preserve the current no-console-flash behavior. The batch verb should set the shell multi-select registry metadata needed for Explorer to invoke the command once for a multi-selection rather than once per selected shortcut.

Update `Uninstall-ContextMenu.ps1` to remove the current DeskPurge verb, any older separate batch verb, and any generated hidden launchers.

## Testing

Add Pester coverage for pure helper behavior:

- Multiple shortcut paths are normalized and deduplicated.
- Public Desktop shortcut paths are classified as needing admin.
- Non-`.lnk` paths are rejected at row level.
- Protected-folder failures produce blocked rows.

Manual verification is required for Explorer integration:

1. Create or use ten desktop `.lnk` shortcuts pointing into safe test game folders under a configured protected root.
2. Select all ten.
3. Shift-right-click the final selected shortcut.
4. Choose `DeskPurge - Uninstall`.
5. Verify one review window opens.
6. Confirm selected ready rows.
7. Verify one completion summary appears.
8. Verify only intended folders and shortcuts were deleted.

CI verification remains:

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning
Invoke-Pester -Path .\tests -CI
```

## Open Implementation Risk

Windows Explorer multi-select context-menu argument passing may vary depending on file association and verb registration. The implementation must validate this early. If Explorer only launches one process per selected file, the plan should switch to a queue-based single-instance aggregator or a drag-and-drop batch window instead of returning to ten popups.
