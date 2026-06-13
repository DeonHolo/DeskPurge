# Plan 003: Fail closed when protected-folder config is missing or invalid

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in "STOP conditions" occurs, stop and report. When done, update this plan's status row in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat bc673f0..HEAD -- DeskPurge.Core.ps1 DeskPurge.ps1 README.md tests/DeskPurge.Core.Tests.ps1`
> `git status --short -- DeskPurge.Core.ps1 DeskPurge.ps1 README.md tests/DeskPurge.Core.Tests.ps1`
> If in-scope files changed, compare "Current state" excerpts against live code before proceeding.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/001-add-pester-safety-tests.md`
- **Category**: bug
- **Planned at**: commit `bc673f0`, 2026-06-12

## Why this matters

The README describes protected folders as the safety boundary that prevents whole-library deletion. The script currently continues with an empty user-protected list when the config file is missing, and it only warns if reading fails. For a permanent-delete tool, missing safety config should stop the operation before target selection and before any confirmation dialog offers a dangerous path.

## Current State

- `Get-ProtectedGameFolders` returns an empty list if the config file does not exist.
- The main script uses that list for traversal and only blocks root drives, system folders, user profile, and desktop.
- Config comments are currently treated as entries because the parser only skips blank lines.

Relevant excerpts:

```powershell
# DeskPurge.ps1:58-74
if (Test-Path $ConfigFile) {
    try {
        Get-Content $ConfigFile | ForEach-Object {
            $line = $_.Trim()
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $normalized = $line.TrimEnd('\').TrimEnd('/').ToLowerInvariant()
                if ($normalized) {
                    $loadedProtectedFolders.Add($normalized)
                }
            }
        }
    }
    catch {
        Show-Popup -Message "Error reading protected folders config file:`n$ConfigFile`n$($_.Exception.Message)" -Title "Config Error" -Type "Warning"
    }
}
return $loadedProtectedFolders
```

```powershell
# DeskPurge.ps1:139-164
$userProtectedGameFolders = Get-ProtectedGameFolders -ConfigFile $ProtectedFoldersConfigFile
...
if ($userProtectedGameFolders -contains $normalizedFolderToDelete) { Show-Popup -Message "SAFETY HALT! Final folder IS a main game library:`n$folderToDelete`nAborting." -Title "DANGER - Main Game Library" -Type "Error" }
```

README evidence:

```markdown
# README.md:17
Without them, DeskPurge could accidentally walk up the folder tree and delete much more than intended, potentially your entire game library
```

Repo conventions:

- Fatal GUI errors use `Show-Popup -Type "Error"`, which exits.
- Warnings use `Show-Popup -Type "Warning"` and continue.

## Commands You Will Need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Lint | `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning` | exit 0, no analyzer findings |
| Test | `Invoke-Pester -Path .\tests -CI` | exit 0, all tests pass |

## Scope

**In scope**:

- `DeskPurge.Core.ps1`
- `DeskPurge.ps1`
- `README.md`
- `tests/DeskPurge.Core.Tests.ps1`
- `plans/README.md` status row only

**Out of scope**:

- Do not change Steam-specific boundaries; plan 002 owns that.
- Do not change `Remove-Item` deletion behavior.
- Do not alter registry install/uninstall scripts.

## Git Workflow

- Branch: `advisor/003-fail-closed-on-missing-config`
- Suggested commit message: `fix: fail closed without protected folder config`
- Do not push unless instructed.

## Steps

### Step 1: Add config parser tests

In `tests/DeskPurge.Core.Tests.ps1`, add tests for the config-loading helper:

- Missing config returns a structured failure, throws a specific error, or otherwise lets the caller distinguish "missing" from "empty but valid".
- Comment lines beginning with `#` are ignored.
- Blank lines are ignored.
- Valid paths are normalized and returned.
- A config with no valid non-comment paths is invalid.

Choose one clear contract and document it in the test names before implementation.

**Verify**: `Invoke-Pester -Path .\tests -CI` -> new tests fail before implementation and existing tests still pass. If unrelated tests fail, STOP.

### Step 2: Make the parser fail closed

Update `DeskPurge.Core.ps1` so config loading has an explicit invalid state. Acceptable implementations:

- Throw a terminating error from `Get-ProtectedGameFolders` when the file is missing, unreadable, or has no valid active entries.
- Or return an object like `{ Success, Folders, ErrorMessage }` and require callers to check `Success`.

Prefer the simpler contract that fits the plan 001 helper shape. The main requirement: `DeskPurge.ps1` must not continue to traversal with an empty protected-folder list caused by a missing or invalid config.

Also skip comment lines:

```powershell
if ($line.StartsWith('#')) { return }
```

Use PowerShell syntax that is valid inside the actual loop; do not paste this fragment blindly if `return` would exit the wrong scope.

**Verify**: `Invoke-Pester -Path .\tests -CI` -> config parser tests pass.

### Step 3: Surface a fatal GUI error in the main script

Update `DeskPurge.ps1` so failures from config loading show a clear `Show-Popup -Type "Error"` before target traversal. The message should include:

- The expected config path.
- That no deletion was attempted.
- That the user must create or fix `DeskPurge_ProtectedFolders.txt`.

Do not allow the main script to continue to confirmation when the config is missing or invalid.

**Verify**: `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning` -> exit 0.

### Step 4: Update README safety wording

Update README installation/safety text to state that `DeskPurge_ProtectedFolders.txt` is required, not merely strongly recommended. Keep the warning plain and direct.

**Verify**: `Select-String -Path .\README.md -Pattern 'required','DeskPurge_ProtectedFolders.txt'` -> finds relevant updated lines.

## Test Plan

- Add Pester unit tests around config parsing and fail-closed behavior.
- If direct GUI behavior is hard to test, keep GUI tests out of scope and test the pure helper contract plus a small wrapper function if plan 001 created one.
- Run lint and tests.

## Done Criteria

- [ ] Missing config cannot produce an empty protected-folder list that traversal uses.
- [ ] Unreadable or comment-only config stops the operation before confirmation.
- [ ] Comment lines in `DeskPurge_ProtectedFolders.txt` are ignored by the parser.
- [ ] README says the config is required.
- [ ] `Invoke-Pester -Path .\tests -CI` exits 0.
- [ ] `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning` exits 0.
- [ ] No files outside scope are modified, except `plans/README.md` status.

## STOP Conditions

Stop and report back if:

- Plan 001 has not landed and there is no testable config-loading helper.
- The chosen parser contract would require changing unrelated script startup behavior.
- Existing users depend on running without a config file and the maintainer rejects fail-closed behavior.
- The live code at the excerpted locations no longer matches the current state above.

## Maintenance Notes

Reviewers should check that "empty by mistake" and "empty by design" are not conflated. For this tool, an empty config should be treated as unsafe unless a future product decision explicitly introduces an advanced override.
