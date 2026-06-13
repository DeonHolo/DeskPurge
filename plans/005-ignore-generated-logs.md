# Plan 005: Ignore generated DeskPurge logs

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in "STOP conditions" occurs, stop and report. When done, update this plan's status row in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat bc673f0..HEAD -- .gitignore DeskPurge.ps1`
> `git status --short -- .gitignore DeskPurge.ps1 DeskPurge_Log.txt`
> If in-scope files changed, compare "Current state" excerpts against live code before proceeding.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `bc673f0`, 2026-06-12

## Why this matters

`DeskPurge.ps1` writes `DeskPurge_Log.txt` in the repo/script directory. That log contains local shortcut paths, deleted folder paths, and uninstall history. Because the current `.gitignore` ignores `*.log` but not this `.txt` file, the generated log can appear as an untracked file and be committed accidentally.

## Current State

Relevant excerpts:

```powershell
# DeskPurge.ps1:258-260
# 7. Log
$logFile   = Join-Path $PSScriptRoot "DeskPurge_Log.txt"
$timestamp = Get-Date -Format 'yyyy-MM-dd hh:mm tt'
```

```gitignore
# .gitignore:1-6
Test/
*.log
*.tmp
*.bak
.DS_Store
Thumbs.db
```

At planning time `DeskPurge_Log.txt` existed as an untracked local file. Do not read, copy, or commit its contents.

Repo conventions:

- Generated local artifacts belong in `.gitignore`.
- Do not remove user-local untracked files unless the operator explicitly asks.

## Commands You Will Need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Ignore check | `git check-ignore -v DeskPurge_Log.txt` | exits 0 and shows `.gitignore` rule |
| Lint | `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning` | exit 0, no analyzer findings |

## Scope

**In scope**:

- `.gitignore`
- `plans/README.md` status row only

**Out of scope**:

- Do not delete `DeskPurge_Log.txt`.
- Do not open, quote, summarize, or commit log contents.
- Do not change where the script writes logs unless the maintainer asks for that separately.

## Git Workflow

- Branch: `advisor/005-ignore-generated-logs`
- Suggested commit message: `chore: ignore DeskPurge generated logs`
- Do not push unless instructed.

## Steps

### Step 1: Add explicit ignore entries

Update `.gitignore` to include:

```gitignore
DeskPurge_Log.txt
DeskPurge_CriticalError.txt
```

The critical-error file is normally written to `%TEMP%`, but ignoring it is harmless if someone runs or copies it near the repo.

**Verify**: `git check-ignore -v DeskPurge_Log.txt` -> exits 0 and points to `.gitignore`.

### Step 2: Check git status

Run:

```powershell
git status --short
```

`DeskPurge_Log.txt` should no longer appear as an untracked file. Existing unrelated files like `.vscode/settings.json` may still appear; do not touch them.

**Verify**: `git status --short -- DeskPurge_Log.txt` -> no output.

## Test Plan

- No behavior tests are needed because this is ignore metadata only.
- Run lint only if source scripts changed; they should not change in this plan.

## Done Criteria

- [ ] `.gitignore` explicitly ignores `DeskPurge_Log.txt`.
- [ ] `git check-ignore -v DeskPurge_Log.txt` exits 0.
- [ ] `git status --short -- DeskPurge_Log.txt` prints no output.
- [ ] No files outside scope are modified, except `plans/README.md` status.

## STOP Conditions

Stop and report back if:

- `DeskPurge_Log.txt` is already tracked in git; ignoring alone will not remove a tracked file.
- The maintainer wants logs versioned for fixtures or examples.
- The live `.gitignore` no longer matches the current state above.

## Maintenance Notes

If the log path changes later, update `.gitignore` in the same change. Reviewers should reject PRs that include real local uninstall logs.
