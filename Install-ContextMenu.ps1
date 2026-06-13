param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot "DeskPurge.ps1"),
    [string]$VerbKeyName = "DeskPurge",
    [string]$VerbName = "DeskPurge - Uninstall"
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

Remove-LegacyDeskPurgeUninstallVerb -CurrentScriptPath $ScriptPath

$scriptDirectory = Split-Path -Path $ScriptPath -Parent
$launcherPath = Join-Path -Path $scriptDirectory -ChildPath "DeskPurge.Hidden.vbs"
$escapedScriptPath = $ScriptPath.Replace('"', '""')
$launcherContent = @"
Option Explicit

Dim shell, scriptPath, linkPath, command
Set shell = CreateObject("WScript.Shell")

scriptPath = "$escapedScriptPath"
linkPath = ""

If WScript.Arguments.Count > 0 Then
    linkPath = WScript.Arguments(0)
End If

command = "powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File " & Quote(scriptPath)

If Len(linkPath) > 0 Then
    command = command & " " & Quote(linkPath)
End If

shell.Run command, 0, False

Function Quote(value)
    Quote = Chr(34) & Replace(value, Chr(34), Chr(34) & Chr(34)) & Chr(34)
End Function
"@

Set-Content -LiteralPath $launcherPath -Value $launcherContent -Encoding ASCII

$verbKey = "HKCU:\Software\Classes\lnkfile\shell\$VerbKeyName"
$cmdKey  = Join-Path $verbKey "command"

New-Item -Path $verbKey -Force | Out-Null
New-ItemProperty -Path $verbKey -Name "(default)" -Value $VerbName -PropertyType String -Force | Out-Null
New-ItemProperty -Path $verbKey -Name "Extended" -Value "" -PropertyType String -Force | Out-Null  # Shift+Right-Click only
New-ItemProperty -Path $verbKey -Name "Icon" -Value "wscript.exe" -PropertyType String -Force | Out-Null

New-Item -Path $cmdKey -Force | Out-Null
$cmd = "wscript.exe //nologo `"$launcherPath`" `"%1`""
New-ItemProperty -Path $cmdKey -Name "(default)" -Value $cmd -PropertyType String -Force | Out-Null

Write-Host "DeskPurge context menu installed for .lnk (Shift+Right-Click)."
Write-Host "Hidden launcher written to: $launcherPath"
