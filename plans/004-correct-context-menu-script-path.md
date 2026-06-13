# Plan 004: Correct the context-menu installer default script path

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in "STOP conditions" occurs, stop and report. When done, update this plan's status row in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat bc673f0..HEAD -- Install-ContextMenu.ps1 README.md`
> `git status --short -- Install-ContextMenu.ps1 README.md`
> If in-scope files changed, compare "Current state" excerpts against live code before proceeding.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `bc673f0`, 2026-06-12

## Why this matters

The README tells users to place `Install-ContextMenu.ps1` and `DeskPurge.ps1` in the same directory. The installer default currently looks one directory above the installer for `DeskPurge.ps1`, so running it from this repo root writes a registry command to a non-existent script path. That makes the installed context menu fail when clicked.

## Current State

Relevant excerpts:

```powershell
# Install-ContextMenu.ps1:1-3
param(
    [string]$ScriptPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "DeskPurge.ps1"),
    [string]$VerbKeyName = "DeskPurge",
```

```powershell
# Install-ContextMenu.ps1:17-18
$cmd = "powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$ScriptPath`" `"%1`""
New-ItemProperty -Path $cmdKey -Name "(default)" -Value $cmd -PropertyType String -Force | Out-Null
```

README evidence:

```markdown
# README.md:33
2) Place the files in the same directory (anywhere you prefer).
```

Read-only simulation during audit:

- Repo root: `D:\Games\1. Steamless\UNINSTALL SCRIPT FROM DESKTOP`
- Current default resolves to: `D:\Games\1. Steamless\DeskPurge.ps1`
- That path did not exist in this workspace.

Repo conventions:

- Installer writes under `HKCU:\Software\Classes\lnkfile\shell\...`.
- The script intentionally uses `-WindowStyle Hidden` and `-ExecutionPolicy Bypass`; do not change those in this plan.

## Commands You Will Need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Lint | `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning` | exit 0, no analyzer findings |
| Static path check | `Select-String -Path .\Install-ContextMenu.ps1 -Pattern 'Join-Path \$PSScriptRoot "DeskPurge.ps1"'` | finds one matching line |

Do not run `Install-ContextMenu.ps1` as a verification step unless the operator explicitly wants the registry modified.

## Scope

**In scope**:

- `Install-ContextMenu.ps1`
- `README.md` only if the installer usage text needs clarification
- `plans/README.md` status row only

**Out of scope**:

- Do not modify registry keys during verification.
- Do not change `Uninstall-ContextMenu.ps1`.
- Do not change the hidden PowerShell command form.
- Do not edit main deletion logic.

## Git Workflow

- Branch: `advisor/004-correct-context-menu-script-path`
- Suggested commit message: `fix: point context menu installer at local DeskPurge script`
- Do not push unless instructed.

## Steps

### Step 1: Fix the default path

Change the default `ScriptPath` parameter to point to `DeskPurge.ps1` in the same directory as `Install-ContextMenu.ps1`:

```powershell
[string]$ScriptPath = (Join-Path $PSScriptRoot "DeskPurge.ps1")
```

Keep the parameter override available so advanced users can still pass a custom path.

**Verify**: `Select-String -Path .\Install-ContextMenu.ps1 -Pattern 'Join-Path \$PSScriptRoot "DeskPurge.ps1"'` -> one matching line.

### Step 2: Add a preflight path check

Before writing registry keys, add a check:

```powershell
if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    throw "DeskPurge script not found: $ScriptPath"
}
```

This prevents installing a broken context-menu command.

**Verify**: `Invoke-ScriptAnalyzer -Path .\Install-ContextMenu.ps1 -Severity Error,Warning` -> exit 0, no analyzer findings.

### Step 3: Clarify README if needed

If README still implies a different folder layout, update it to say the default installer expects `Install-ContextMenu.ps1` and `DeskPurge.ps1` beside each other, or that `-ScriptPath` can be supplied for a custom location.

**Verify**: `Select-String -Path .\README.md -Pattern 'same directory','ScriptPath'` -> finds the updated guidance. If no README change was needed, explain that in the plan status update.

## Test Plan

- Static verification is enough for this small script because running it writes registry keys.
- Optionally, if plan 001 has landed, add a Pester test that parses the script text and asserts the default path expression uses `$PSScriptRoot` directly. Do not execute the installer in tests.

## Done Criteria

- [ ] Default `ScriptPath` points to `Join-Path $PSScriptRoot "DeskPurge.ps1"`.
- [ ] Installer throws before registry writes if the script path does not exist.
- [ ] `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning` exits 0.
- [ ] No registry writes are performed as part of verification.
- [ ] No files outside scope are modified, except `plans/README.md` status.

## STOP Conditions

Stop and report back if:

- The repo has been reorganized and `DeskPurge.ps1` is no longer intended to sit beside the installer.
- Verifying the fix appears to require running the installer and mutating HKCU without operator approval.
- The live code at the excerpted locations no longer matches the current state above.

## Maintenance Notes

If installer scripts move back under a `tools/` directory in the future, this default path must be revisited. The preflight check should remain even if the path formula changes.
