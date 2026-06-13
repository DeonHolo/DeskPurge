# Plan 001: Add Pester safety tests around deletion-target selection

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in "STOP conditions" occurs, stop and report. When done, update this plan's status row in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat bc673f0..HEAD -- DeskPurge.ps1 .github/workflows/ci.yml .gitignore`
> `git status --short -- DeskPurge.ps1 .github/workflows/ci.yml .gitignore tests`
> If any in-scope file changed since this plan was written, compare "Current state" excerpts against live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `bc673f0`, 2026-06-12

## Why this matters

`DeskPurge.ps1` permanently deletes folders. The risky logic that decides which folder to delete is currently embedded in top-level GUI code, so it is hard to test without invoking the real script. Extracting pure helpers and adding Pester tests gives later safety fixes a reliable verification path.

## Current state

- `DeskPurge.ps1` is the main destructive script. It resolves `.lnk` targets, walks upward, confirms with the user, and then deletes the selected folder.
- `.github/workflows/ci.yml` only installs and runs PSScriptAnalyzer.
- No tracked `*.Tests.ps1` file exists. `rg --files -g '*.Tests.ps1'` returned no matches during recon.

Relevant excerpts:

```powershell
# DeskPurge.ps1:54-75
function Get-ProtectedGameFolders {
    param([string]$ConfigFile)
    $loadedProtectedFolders = [System.Collections.Generic.List[string]]::new()
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
}
```

```powershell
# DeskPurge.ps1:142-158
$folderToDelete = $initialFolderCandidate
Write-Host "DEBUG: Initial folder candidate: $folderToDelete"
for ($i = 0; $i -lt 10; $i++) {
    $parentOfCurrentFolder = Split-Path -Path $folderToDelete -Parent
    if ([string]::IsNullOrWhiteSpace($parentOfCurrentFolder)) { Write-Host "DEBUG: Reached root or invalid parent."; break }
    $normalizedParent = $parentOfCurrentFolder.TrimEnd('\').TrimEnd('/').ToLowerInvariant()
    Write-Host "DEBUG: Checking parent: $normalizedParent (of current $folderToDelete)"
    if (($normalizedParent -match '^[a-z]:\\?$') -or ($systemProtectedPaths -contains $normalizedParent) -or ($userProtectedGameFolders -contains $normalizedParent)) {
        Write-Host "DEBUG: Parent '$normalizedParent' is protected. '$folderToDelete' is the target."
        break
    }
    $folderToDelete = $parentOfCurrentFolder
    Write-Host "DEBUG: Moved up. New folderToDelete: $folderToDelete"
    if (($folderToDelete.TrimEnd('\').TrimEnd('/').ToLowerInvariant()) -match '^[a-z]:\\?$') { Write-Host "DEBUG: New folderToDelete '$folderToDelete' is a root drive."; break }
}
```

Repo conventions:

- PowerShell scripts live at repo root and use simple functions, `param(...)`, `Write-Host`, and explicit `-LiteralPath` for filesystem deletion.
- CI uses `pwsh` on `windows-latest`.
- Commit messages in recent history use conventional prefixes such as `docs:`, `fix:`, `feat:`, `ci:`, and `test:`.

## Commands You Will Need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Lint | `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning` | exit 0, no analyzer findings |
| Test | `Invoke-Pester -Path .\tests -CI` | exit 0, all tests pass |

If `Invoke-Pester` is not available locally, install Pester only with operator approval if your environment requires approval for network/module installs:

```powershell
Install-Module Pester -Scope CurrentUser -Force -MinimumVersion 5.5.0
```

## Scope

**In scope**:

- `DeskPurge.ps1`
- `DeskPurge.Core.ps1` (create)
- `tests/DeskPurge.Core.Tests.ps1` (create)
- `.github/workflows/ci.yml`
- `.gitignore` only if needed to ensure `tests/` is trackable
- `plans/README.md` status row only

**Out of scope**:

- Do not change the actual deletion policy yet. Plans 002 and 003 do that.
- Do not change registry installer behavior. Plan 004 does that.
- Do not delete or rewrite the user's untracked `DeskPurge_Log.txt`.

## Git Workflow

- Branch: `advisor/001-pester-safety-tests`
- Suggested commit message: `test: add DeskPurge deletion-target safety coverage`
- Do not push unless the operator instructed it.

## Steps

### Step 1: Create a pure core script

Create `DeskPurge.Core.ps1` and move or duplicate only pure, non-GUI helpers into it:

- `Normalize-DeskPurgePath` for trimming slashes and lowercasing paths.
- `Format-FileSize`, preserving current behavior.
- `Get-ProtectedGameFolders`, preserving current behavior for this plan except it may use `Normalize-DeskPurgePath`.
- `Resolve-DeskPurgeDeletionTarget`, containing the upward traversal from `DeskPurge.ps1:142-158`.

The first implementation should intentionally preserve the current traversal semantics so tests can capture existing behavior before later plans change it.

Update `DeskPurge.ps1` to dot-source the core file near the top:

```powershell
. (Join-Path -Path $PSScriptRoot -ChildPath 'DeskPurge.Core.ps1')
```

Then replace the inline traversal block with a call to `Resolve-DeskPurgeDeletionTarget`. Keep final safety checks in `DeskPurge.ps1` for now.

**Verify**: `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning` -> exit 0, no analyzer findings.

### Step 2: Add Pester tests for target selection

Create `tests/DeskPurge.Core.Tests.ps1`. Dot-source `DeskPurge.Core.ps1` from the repo root. Add tests for at least:

- `D:\Games\CoolGame\bin\game.exe` with protected path `D:\Games` returns `D:\Games\CoolGame`.
- `D:\Games\CoolGame` with protected path `D:\Games` returns `D:\Games\CoolGame`.
- A target whose parent is a drive root must not return the root as a safe deletion target.
- Current Steam behavior is captured in a pending or clearly named regression test for plan 002. If using Pester `It -Pending`, name it: `returns the game folder for Steam libraries configured at the library root`.
- Current missing-config behavior is captured in a pending or clearly named regression test for plan 003.

Use Pester `TestDrive:` for any filesystem fixtures if needed. Prefer testing pure path strings without creating real game folders.

**Verify**: `Invoke-Pester -Path .\tests -CI` -> exit 0. Pending tests may be reported as skipped/pending, but no failures.

### Step 3: Wire tests into CI

Update `.github/workflows/ci.yml` to install Pester and run tests after lint. Keep the existing PSScriptAnalyzer step.

Expected structure:

```yaml
- name: Install Pester
  shell: pwsh
  run: Install-Module Pester -Scope CurrentUser -Force -MinimumVersion 5.5.0
- name: Run Pester
  shell: pwsh
  run: Invoke-Pester -Path .\tests -CI
```

**Verify**: `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning` -> exit 0; `Invoke-Pester -Path .\tests -CI` -> exit 0.

## Test Plan

- New file: `tests/DeskPurge.Core.Tests.ps1`.
- Cover normal protected-folder traversal, root-drive refusal behavior, and pending regression cases for plans 002 and 003.
- Do not run `DeskPurge.ps1` against real shortcuts or real game folders.

## Done Criteria

- [ ] `DeskPurge.Core.ps1` exists and contains pure helper functions.
- [ ] `DeskPurge.ps1` uses the core helper for deletion-target selection.
- [ ] `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning` exits 0.
- [ ] `Invoke-Pester -Path .\tests -CI` exits 0.
- [ ] CI runs both lint and Pester tests.
- [ ] No files outside the in-scope list are modified, except `plans/README.md` status.

## STOP Conditions

Stop and report back if:

- Dot-sourcing `DeskPurge.Core.ps1` causes the main script to display GUI prompts or exit during tests.
- Extracting the traversal requires changing deletion behavior before tests exist.
- Pester cannot be installed or run in the target environment after one reasonable attempt.
- The live code at the excerpted locations no longer matches the current state above.

## Maintenance Notes

Future changes to folder selection should add or update Pester tests first. Reviewers should scrutinize this plan for accidental behavior changes: plan 001 is primarily a safety harness, not a policy change.
