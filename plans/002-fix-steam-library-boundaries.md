# Plan 002: Make Steam library boundaries delete the game folder, not `steamapps`

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in "STOP conditions" occurs, stop and report. When done, update this plan's status row in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat bc673f0..HEAD -- DeskPurge.Core.ps1 DeskPurge.ps1 DeskPurge_ProtectedFolders.txt README.md tests/DeskPurge.Core.Tests.ps1`
> `git status --short -- DeskPurge.Core.ps1 DeskPurge.ps1 DeskPurge_ProtectedFolders.txt README.md tests/DeskPurge.Core.Tests.ps1`
> If in-scope files changed, compare "Current state" excerpts against live code before proceeding; preserve user edits in `DeskPurge_ProtectedFolders.txt`.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MED
- **Depends on**: `plans/001-add-pester-safety-tests.md`
- **Category**: bug
- **Planned at**: commit `bc673f0`, 2026-06-12

## Why this matters

The default protected-folder config includes Steam library roots such as `D:\SteamLibrary`. With the current upward traversal, a shortcut under `D:\SteamLibrary\steamapps\common\Game\...` selects `D:\SteamLibrary\steamapps` for deletion. That can remove multiple Steam games instead of the one selected game.

## Current State

- `DeskPurge_ProtectedFolders.txt` is the user-editable boundary file. At planning time it had local user additions (`D:\~Games~`, `D:\Games2`) that must be preserved.
- The upward traversal stops when the parent of the current folder is protected, then deletes the current folder.

Relevant excerpts:

```text
# DeskPurge_ProtectedFolders.txt:20-23
# Steam libraries:
C:\Program Files (x86)\Steam\steamapps\common
D:\SteamLibrary
E:\SteamLibrary
```

```powershell
# DeskPurge.ps1:148-154
$normalizedParent = $parentOfCurrentFolder.TrimEnd('\').TrimEnd('/').ToLowerInvariant()
if (($normalizedParent -match '^[a-z]:\\?$') -or ($systemProtectedPaths -contains $normalizedParent) -or ($userProtectedGameFolders -contains $normalizedParent)) {
    Write-Host "DEBUG: Parent '$normalizedParent' is protected. '$folderToDelete' is the target."
    break
}
$folderToDelete = $parentOfCurrentFolder
```

Read-only simulation performed during audit:

- Input target parent: `D:\SteamLibrary\steamapps\common\ExampleGame\bin`
- Protected path: `D:\SteamLibrary`
- Current result: `D:\SteamLibrary\steamapps`

Repo conventions:

- Keep user-configurable protected folders in `DeskPurge_ProtectedFolders.txt`.
- Keep safety logic in PowerShell helpers added by plan 001.

## Commands You Will Need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Lint | `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning` | exit 0, no analyzer findings |
| Test | `Invoke-Pester -Path .\tests -CI` | exit 0, all tests pass |

## Scope

**In scope**:

- `DeskPurge.Core.ps1`
- `DeskPurge.ps1` only if needed to consume a changed helper contract
- `DeskPurge_ProtectedFolders.txt`
- `README.md`
- `tests/DeskPurge.Core.Tests.ps1`
- `plans/README.md` status row only

**Out of scope**:

- Do not remove user-added protected paths like `D:\~Games~` or `D:\Games2`.
- Do not change deletion execution (`Remove-Item`) in this plan.
- Do not add launcher-specific uninstall behavior.

## Git Workflow

- Branch: `advisor/002-fix-steam-library-boundaries`
- Suggested commit message: `fix: protect Steam common folders when selecting deletion target`
- Do not push unless instructed.

## Steps

### Step 1: Add failing Steam regression tests

In `tests/DeskPurge.Core.Tests.ps1`, add or un-pend tests that assert:

- A target under `D:\SteamLibrary\steamapps\common\ExampleGame\bin` with configured boundary `D:\SteamLibrary` resolves to `D:\SteamLibrary\steamapps\common\ExampleGame`.
- A target under `E:\SteamLibrary\steamapps\common\ExampleGame\game.exe` with configured boundary `E:\SteamLibrary` resolves to `E:\SteamLibrary\steamapps\common\ExampleGame`.
- A target under `C:\Program Files (x86)\Steam\steamapps\common\ExampleGame\bin` with configured boundary `C:\Program Files (x86)\Steam\steamapps\common` still resolves to the game folder.

**Verify**: `Invoke-Pester -Path .\tests -CI` -> tests should fail only on the newly enabled Steam cases before the fix. If unrelated tests fail, STOP.

### Step 2: Expand Steam library roots into `steamapps\common` boundaries

In `DeskPurge.Core.ps1`, update protected-folder loading or normalization so a configured Steam library root also protects its `steamapps\common` child. For example, if a configured path ends with `SteamLibrary`, include both:

- `d:\steamlibrary`
- `d:\steamlibrary\steamapps\common`

Do this generically enough for common Steam library roots, not only `D:` and `E:`. A simple rule is acceptable: for every configured protected folder, also add `<configured>\steamapps\common` unless the configured folder already ends with `steamapps\common`. Deduplicate normalized paths.

Keep existing non-Steam behavior unchanged.

**Verify**: `Invoke-Pester -Path .\tests -CI` -> Steam tests pass and existing tests pass.

### Step 3: Fix defaults and docs

Update `DeskPurge_ProtectedFolders.txt` so example Steam entries teach the safer boundary:

```text
D:\SteamLibrary\steamapps\common
E:\SteamLibrary\steamapps\common
```

Preserve local user additions and other examples. Update `README.md` if it says Steam library roots should be used directly; explain that for Steam, the game-folder parent is usually `...\steamapps\common`.

**Verify**: `Select-String -Path .\DeskPurge_ProtectedFolders.txt -Pattern 'D:\\SteamLibrary\\steamapps\\common','E:\\SteamLibrary\\steamapps\\common'` -> both patterns are found.

## Test Plan

- Tests in `tests/DeskPurge.Core.Tests.ps1` must cover Steam root input and explicit `steamapps\common` input.
- The regression test must assert the exact deletion target path, not only "not steamapps".
- Run both lint and tests.

## Done Criteria

- [ ] Steam library roots no longer resolve to `steamapps` as the deletion target.
- [ ] `D:\SteamLibrary\steamapps\common` and `E:\SteamLibrary\steamapps\common` are documented/configured as examples.
- [ ] `Invoke-Pester -Path .\tests -CI` exits 0.
- [ ] `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning` exits 0.
- [ ] User-added config entries are preserved.
- [ ] No files outside scope are modified, except `plans/README.md` status.

## STOP Conditions

Stop and report back if:

- Plan 001 has not landed and no Pester harness exists.
- The live target-selection helper is materially different from plan 001's expected helper.
- Fixing Steam paths would require changing the confirmation or deletion code.
- User edits in `DeskPurge_ProtectedFolders.txt` conflict with the example updates.

## Maintenance Notes

Reviewers should check that this fix does not special-case one drive letter. Future launcher-specific examples should point to the parent folder that directly contains one game folder per child.
