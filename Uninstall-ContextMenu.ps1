param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot "DeskPurge.ps1"),
    [string]$VerbKeyName = "DeskPurge"
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
        if ($command -notlike "*DeskPurge.ps1*" -and $command -notlike "*$ScriptPath*") {
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

$verbKey = "HKCU:\Software\Classes\lnkfile\shell\$VerbKeyName"
Remove-DeskPurgeRegistryKeyIfPresent -Path $verbKey
Remove-DeskPurgeRegistryKeyIfPresent -Path "HKCU:\Software\Classes\lnkfile\shell\Uninstall" -OnlyIfDeskPurgeCommand
Remove-DeskPurgeRegistryKeyIfPresent -Path "HKLM:\Software\Classes\lnkfile\shell\Uninstall" -OnlyIfDeskPurgeCommand

$launcherPath = Join-Path -Path (Split-Path -Path $ScriptPath -Parent) -ChildPath "DeskPurge.Hidden.vbs"
if (Test-Path -LiteralPath $launcherPath -PathType Leaf) {
    Remove-Item -LiteralPath $launcherPath -Force
    Write-Host "Removed hidden launcher: $launcherPath"
}
