param(
    [string]$VerbKeyName = "DeskPurge"
)

$verbKey = "HKCU:\Software\Classes\lnkfile\shell\$VerbKeyName"
if (Test-Path $verbKey) {
    Remove-Item -Path $verbKey -Recurse -Force
    Write-Host "DeskPurge context menu removed."
} else {
    Write-Host "DeskPurge context menu not found."
}
