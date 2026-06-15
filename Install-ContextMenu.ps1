param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot "DeskPurge.ps1"),
    [string]$VerbKeyName = "DeskPurge",
    [string]$VerbName = "DeskPurge - Uninstall",
    [string]$LegacyBatchVerbKeyName = "DeskPurgeBatch"
)

if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    throw "DeskPurge script not found: $ScriptPath"
}

function Remove-LegacyDeskPurgeUninstallVerb {
    param([Parameter(Mandatory = $true)][string]$CurrentScriptPath)

    $legacyKeys = @(
        "HKCU:\Software\Classes\lnkfile\shell\Uninstall",
        "HKLM:\Software\Classes\lnkfile\shell\Uninstall"
    )

    foreach ($legacyKey in $legacyKeys) {
        $legacyCommandKey = Join-Path -Path $legacyKey -ChildPath "command"
        if (-not (Test-Path -LiteralPath $legacyCommandKey)) {
            continue
        }

        $legacyCommand = (Get-ItemProperty -LiteralPath $legacyCommandKey)."(default)"
        $isDeskPurgeCommand = $legacyCommand -like "*DeskPurge.ps1*" -or $legacyCommand -like "*$CurrentScriptPath*"
        if (-not $isDeskPurgeCommand) {
            continue
        }

        try {
            Remove-Item -LiteralPath $legacyKey -Recurse -Force -ErrorAction Stop
            Write-Host "Removed old DeskPurge context menu key: $legacyKey"
        }
        catch {
            Write-Warning "Could not remove old DeskPurge context menu key '$legacyKey'. Run this installer as administrator to remove all-users legacy entries."
        }
    }
}

function New-DeskPurgeHiddenLauncher {
    param(
        [Parameter(Mandatory = $true)][string]$LauncherPath,
        [Parameter(Mandatory = $true)][string]$TargetScriptPath
    )

    $escapedScriptPath = $TargetScriptPath.Replace('"', '""')
    $launcherContent = @"
Option Explicit

Dim shell, scriptPath, command, index
Set shell = CreateObject("WScript.Shell")

scriptPath = "$escapedScriptPath"
command = "powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File " & Quote(scriptPath)

For index = 0 To WScript.Arguments.Count - 1
    command = command & " " & Quote(WScript.Arguments(index))
Next

shell.Run command, 0, False

Function Quote(value)
    Quote = Chr(34) & Replace(value, Chr(34), Chr(34) & Chr(34)) & Chr(34)
End Function
"@

    Set-Content -LiteralPath $LauncherPath -Value $launcherContent -Encoding ASCII
}

function Install-DeskPurgeContextMenuVerb {
    param(
        [Parameter(Mandatory = $true)][string]$VerbKeyName,
        [Parameter(Mandatory = $true)][string]$VerbName,
        [Parameter(Mandatory = $true)][string]$Command,
        [switch]$SupportsMultiSelect
    )

    $verbKey = "HKCU:\Software\Classes\lnkfile\shell\$VerbKeyName"
    $cmdKey = Join-Path $verbKey "command"

    New-Item -Path $verbKey -Force | Out-Null
    New-ItemProperty -Path $verbKey -Name "(default)" -Value $VerbName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $verbKey -Name "Extended" -Value "" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $verbKey -Name "Icon" -Value "wscript.exe" -PropertyType String -Force | Out-Null
    if ($SupportsMultiSelect) {
        New-ItemProperty -Path $verbKey -Name "MultiSelectModel" -Value "Player" -PropertyType String -Force | Out-Null
    }

    New-Item -Path $cmdKey -Force | Out-Null
    New-ItemProperty -Path $cmdKey -Name "(default)" -Value $Command -PropertyType String -Force | Out-Null
}

Remove-LegacyDeskPurgeUninstallVerb -CurrentScriptPath $ScriptPath

$scriptDirectory = Split-Path -Path $ScriptPath -Parent
$launcherPath = Join-Path -Path $scriptDirectory -ChildPath "DeskPurge.Hidden.vbs"
$legacyBatchLauncherPath = Join-Path -Path $scriptDirectory -ChildPath "DeskPurge.Batch.Hidden.vbs"

New-DeskPurgeHiddenLauncher -LauncherPath $launcherPath -TargetScriptPath $ScriptPath

$command = "wscript.exe //nologo `"$launcherPath`" `"%1`" %*"

Install-DeskPurgeContextMenuVerb -VerbKeyName $VerbKeyName -VerbName $VerbName -Command $command -SupportsMultiSelect

$legacyBatchVerbKey = "HKCU:\Software\Classes\lnkfile\shell\$LegacyBatchVerbKeyName"
if (Test-Path -LiteralPath $legacyBatchVerbKey) {
    Remove-Item -LiteralPath $legacyBatchVerbKey -Recurse -Force
    Write-Host "Removed old separate batch context menu key: $legacyBatchVerbKey"
}
if (Test-Path -LiteralPath $legacyBatchLauncherPath -PathType Leaf) {
    Remove-Item -LiteralPath $legacyBatchLauncherPath -Force
    Write-Host "Removed old batch hidden launcher: $legacyBatchLauncherPath"
}

Write-Host "DeskPurge context menu installed for .lnk (Shift+Right-Click)."
Write-Host "Launcher written to: $launcherPath"
