# Plan 006: Stream folder-size calculation instead of materializing every item

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in "STOP conditions" occurs, stop and report. When done, update this plan's status row in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat bc673f0..HEAD -- DeskPurge.Core.ps1 DeskPurge.ps1 tests/DeskPurge.Core.Tests.ps1`
> `git status --short -- DeskPurge.Core.ps1 DeskPurge.ps1 tests/DeskPurge.Core.Tests.ps1`
> If in-scope files changed, compare "Current state" excerpts against live code before proceeding.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/001-add-pester-safety-tests.md`
- **Category**: perf
- **Planned at**: commit `bc673f0`, 2026-06-12

## Why this matters

Before showing the confirmation dialog, `DeskPurge.ps1` recursively gets every item under the target folder and stores the collection in `$items`. Large game installs can contain many files, so this can waste memory and delay the confirmation prompt. Streaming the size accumulation keeps the same user-facing result while reducing memory pressure.

## Current State

Relevant excerpt:

```powershell
# DeskPurge.ps1:167-175
$folderSizeDisplay = "N/A"
try {
    if (Test-Path -LiteralPath $folderToDelete -PathType Container) {
        $items = Get-ChildItem -LiteralPath $folderToDelete -Recurse -Force -ErrorAction SilentlyContinue
        if ($items) { $sizeInfo = $items | Measure-Object -Property Length -Sum; $folderSizeBytes = $sizeInfo.Sum; $folderSizeDisplay = Format-FileSize -bytes $folderSizeBytes } 
        else { $folderSizeDisplay = "0 B (or items inaccessible)" }
    }
} catch { $folderSizeDisplay = "Error calculating size" }
```

Repo conventions:

- User-facing size formatting uses `Format-FileSize`.
- Inaccessible files currently do not block deletion preview; `Get-ChildItem` uses `-ErrorAction SilentlyContinue`.
- Main script favors straightforward PowerShell over heavy abstractions.

## Commands You Will Need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Lint | `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning` | exit 0, no analyzer findings |
| Test | `Invoke-Pester -Path .\tests -CI` | exit 0, all tests pass |

## Scope

**In scope**:

- `DeskPurge.Core.ps1`
- `DeskPurge.ps1`
- `tests/DeskPurge.Core.Tests.ps1`
- `plans/README.md` status row only

**Out of scope**:

- Do not change deletion target selection.
- Do not change confirmation wording except the size string if needed.
- Do not make inaccessible files fatal in this plan.

## Git Workflow

- Branch: `advisor/006-stream-folder-size-calculation`
- Suggested commit message: `perf: stream DeskPurge folder size calculation`
- Do not push unless instructed.

## Steps

### Step 1: Add tests for size formatting/calculation

If plan 001 moved `Format-FileSize` into `DeskPurge.Core.ps1`, add tests in `tests/DeskPurge.Core.Tests.ps1` for:

- `Format-FileSize -bytes 0` returns `0 B`.
- A small folder with two files reports the expected combined display.
- An empty folder returns `0 B` or the existing empty-folder message, depending on the helper contract.

Use Pester `TestDrive:` to create temporary files. Do not use real game folders.

**Verify**: `Invoke-Pester -Path .\tests -CI` -> new tests fail only if the helper has not been implemented yet; existing tests pass.

### Step 2: Extract a streaming helper

Add a helper such as `Get-DeskPurgeFolderSizeDisplay` in `DeskPurge.Core.ps1`. It should:

- Accept a folder path.
- Initialize a `[long]` total to `0`.
- Iterate over `Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue`.
- Add each file's `Length` to the total.
- Return `Format-FileSize -bytes $total`.
- Return `"Error calculating size"` only if the overall calculation throws.

Avoid assigning the entire `Get-ChildItem` result to a variable.

**Verify**: `Select-String -Path .\DeskPurge.ps1,.\DeskPurge.Core.ps1 -Pattern '\$items\s*=\s*Get-ChildItem'` -> no output.

### Step 3: Use the helper in `DeskPurge.ps1`

Replace the inline size block in `DeskPurge.ps1` with a call to the helper. Preserve the user-facing behavior that size calculation failure does not abort the uninstall flow.

**Verify**: `Invoke-Pester -Path .\tests -CI` -> all tests pass.

### Step 4: Run lint

Run:

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning
```

**Verify**: exit 0, no analyzer findings.

## Test Plan

- Use Pester `TestDrive:` for folder-size tests.
- Do not create large files; small byte counts are enough to verify summing.
- Assert that the old `$items = Get-ChildItem` materialization pattern is absent.

## Done Criteria

- [ ] No code assigns the full recursive `Get-ChildItem` result to `$items` for size preview.
- [ ] Folder size calculation streams file lengths.
- [ ] Size calculation failure still produces `"Error calculating size"` and does not abort the script.
- [ ] `Invoke-Pester -Path .\tests -CI` exits 0.
- [ ] `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning` exits 0.
- [ ] No files outside scope are modified, except `plans/README.md` status.

## STOP Conditions

Stop and report back if:

- Plan 001 has not landed and `Format-FileSize` is not testable without running the GUI script.
- The streaming implementation would require changing how confirmation or deletion works.
- Inaccessible files become fatal during implementation.
- The live code at the excerpted location no longer matches the current state above.

## Maintenance Notes

If future work adds progress reporting for large folders, keep this helper streaming. Reviewers should check that the confirmation remains responsive and that no broad filesystem errors are introduced.
