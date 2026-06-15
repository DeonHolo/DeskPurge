param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot "DeskPurge.ps1"),
    [string]$VerbKeyName = "DeskPurge",
    [string]$LegacyBatchVerbKeyName = "DeskPurgeBatch"
)

function Remove-DeskPurgeRegistryKeyIfPresent {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$OnlyIfDeskPurgeCommand
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    if ($OnlyIfDeskPurgeCommand) {
        $commandKey = Join-Path -Path $Path -ChildPath "command"
        if (-not (Test-Path -LiteralPath $commandKey)) {
            return
        }

        $command = (Get-ItemProperty -LiteralPath $commandKey)."(default)"
        $matchesDeskPurge = $command -like "*DeskPurge.ps1*" `
            -or $command -like "*DeskPurge.Batch.ps1*" `
            -or $command -like "*$ScriptPath*"
        if (-not $matchesDeskPurge) {
            return
        }
    }

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        Write-Host "Removed context menu key: $Path"
    }
    catch {
        Write-Warning "Could not remove context menu key '$Path'. Run this uninstaller as administrator to remove all-users entries."
    }
}

function Remove-DeskPurgeLauncherIfPresent {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Remove-Item -LiteralPath $Path -Force
        Write-Host "Removed hidden launcher: $Path"
    }
}

Remove-DeskPurgeRegistryKeyIfPresent -Path "HKCU:\Software\Classes\lnkfile\shell\$VerbKeyName"
Remove-DeskPurgeRegistryKeyIfPresent -Path "HKCU:\Software\Classes\lnkfile\shell\$LegacyBatchVerbKeyName"
Remove-DeskPurgeRegistryKeyIfPresent -Path "HKCU:\Software\Classes\lnkfile\shell\Uninstall" -OnlyIfDeskPurgeCommand
Remove-DeskPurgeRegistryKeyIfPresent -Path "HKLM:\Software\Classes\lnkfile\shell\Uninstall" -OnlyIfDeskPurgeCommand

$scriptDirectory = Split-Path -Path $ScriptPath -Parent
$launcherPath = Join-Path -Path $scriptDirectory -ChildPath "DeskPurge.Hidden.vbs"
$legacyBatchLauncherPath = Join-Path -Path $scriptDirectory -ChildPath "DeskPurge.Batch.Hidden.vbs"

Remove-DeskPurgeLauncherIfPresent -Path $launcherPath
Remove-DeskPurgeLauncherIfPresent -Path $legacyBatchLauncherPath
