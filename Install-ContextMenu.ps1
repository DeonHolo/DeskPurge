param(
    [string]$ScriptPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "DeskPurge.ps1"),
    [string]$VerbKeyName = "DeskPurge",
    [string]$VerbName = "DeskPurge - Uninstall"
)

$verbKey = "HKCU:\Software\Classes\lnkfile\shell\$VerbKeyName"
$cmdKey  = Join-Path $verbKey "command"

New-Item -Path $verbKey -Force | Out-Null
New-ItemProperty -Path $verbKey -Name "(default)" -Value $VerbName -PropertyType String -Force | Out-Null
New-ItemProperty -Path $verbKey -Name "Extended" -Value "" -PropertyType String -Force | Out-Null  # Shift+Right-Click only
New-ItemProperty -Path $verbKey -Name "Icon" -Value "powershell.exe" -PropertyType String -Force | Out-Null

New-Item -Path $cmdKey -Force | Out-Null
# Use user's preferred command form (hidden window)
$cmd = "powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$ScriptPath`" `"%1`""
New-ItemProperty -Path $cmdKey -Name "(default)" -Value $cmd -PropertyType String -Force | Out-Null

Write-Host "DeskPurge context menu installed for .lnk (Shift+Right-Click)."
