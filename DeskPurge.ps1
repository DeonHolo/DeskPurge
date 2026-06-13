# DeskPurge.ps1
param([string]$LinkPathFromContextMenu)

# --- Configuration: Define where to find the protected folders list ---
$ConfigFileName = "DeskPurge_ProtectedFolders.txt"
$ScriptPath = $PSScriptRoot
$ProtectedFoldersConfigFile = Join-Path -Path $ScriptPath -ChildPath $ConfigFileName
. (Join-Path -Path $PSScriptRoot -ChildPath "DeskPurge.Core.ps1")

# --- GUI Helper Functions ---
$script:DeskPurgeGuiInitialized = $false

function Initialize-DeskPurgeGui {
    try {
        if (-not $script:DeskPurgeGuiInitialized) {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            Add-Type -AssemblyName System.Drawing -ErrorAction Stop
            if (-not ('DeskPurge.NativeMethods' -as [type])) {
                Add-Type -TypeDefinition @'
namespace DeskPurge {
    using System;
    using System.Runtime.InteropServices;

    public static class NativeMethods {
        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, int msg, int wParam, int lParam);
    }
}
'@ -ErrorAction Stop
            }
            [System.Windows.Forms.Application]::EnableVisualStyles()
            $script:DeskPurgeGuiInitialized = $true
        }
    }
    catch {
        $criticalErrorLog = Join-Path $env:TEMP "DeskPurge_CriticalError.txt"
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
        "[$timestamp] FATAL SCRIPT ERROR:" | Out-File $criticalErrorLog -Append -Encoding UTF8
        "Could not load Windows Forms for DeskPurge dialogs." | Out-File $criticalErrorLog -Append -Encoding UTF8
        "Script cannot continue as intended." | Out-File $criticalErrorLog -Append -Encoding UTF8
        "---" | Out-File $criticalErrorLog -Append -Encoding UTF8
        try { Start-Process notepad.exe $criticalErrorLog } catch {}
        exit 1
    }
}

function Get-DeskPurgeDialogTheme {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Info', 'Warning', 'Error', 'Question', 'Success')]
        [string]$Type
    )

    switch ($Type) {
        'Error' {
            return @{
                Accent = [System.Drawing.Color]::FromArgb(248, 113, 113)
                AccentStrong = [System.Drawing.Color]::FromArgb(220, 38, 38)
                BadgeBack = [System.Drawing.Color]::FromArgb(69, 10, 10)
                BadgeText = 'ERROR'
            }
        }
        'Warning' {
            return @{
                Accent = [System.Drawing.Color]::FromArgb(251, 191, 36)
                AccentStrong = [System.Drawing.Color]::FromArgb(217, 119, 6)
                BadgeBack = [System.Drawing.Color]::FromArgb(69, 26, 3)
                BadgeText = 'WARNING'
            }
        }
        'Question' {
            return @{
                Accent = [System.Drawing.Color]::FromArgb(203, 213, 225)
                AccentStrong = [System.Drawing.Color]::FromArgb(148, 163, 184)
                BadgeBack = [System.Drawing.Color]::FromArgb(31, 31, 31)
                BadgeText = 'REVIEW'
            }
        }
        'Success' {
            return @{
                Accent = [System.Drawing.Color]::FromArgb(74, 222, 128)
                AccentStrong = [System.Drawing.Color]::FromArgb(22, 163, 74)
                BadgeBack = [System.Drawing.Color]::FromArgb(5, 46, 22)
                BadgeText = 'DONE'
            }
        }
        default {
            return @{
                Accent = [System.Drawing.Color]::FromArgb(148, 163, 184)
                AccentStrong = [System.Drawing.Color]::FromArgb(71, 85, 105)
                BadgeBack = [System.Drawing.Color]::FromArgb(30, 41, 59)
                BadgeText = 'INFO'
            }
        }
    }
}

function Add-DeskPurgeDragRegion {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Form]$Form,
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Control]$Control
    )

    $Control.Add_MouseDown({
        param($sender, $eventArgs)

        if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            [DeskPurge.NativeMethods]::ReleaseCapture() | Out-Null
            [DeskPurge.NativeMethods]::SendMessage($Form.Handle, 0xA1, 0x2, 0) | Out-Null
        }
    })
}

function Set-DeskPurgeButtonStyle {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Button]$Button,
        [ValidateSet('Primary', 'Secondary', 'Danger', 'Quiet')]
        [string]$Variant = 'Primary'
    )

    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.Font = [System.Drawing.Font]::new('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $Button.Height = 40
    $Button.Width = 144
    $Button.Margin = [System.Windows.Forms.Padding]::new(8, 0, 0, 0)
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand

    switch ($Variant) {
        'Danger' {
            $Button.BackColor = [System.Drawing.Color]::FromArgb(220, 38, 38)
            $Button.ForeColor = [System.Drawing.Color]::White
            $Button.FlatAppearance.BorderSize = 0
            $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(239, 68, 68)
            $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(153, 27, 27)
        }
        'Secondary' {
            $Button.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 34)
            $Button.ForeColor = [System.Drawing.Color]::FromArgb(232, 229, 222)
            $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80, 76, 68)
            $Button.FlatAppearance.BorderSize = 1
            $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(47, 45, 40)
            $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(60, 56, 50)
        }
        'Quiet' {
            $Button.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 23)
            $Button.ForeColor = [System.Drawing.Color]::FromArgb(194, 187, 176)
            $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(58, 55, 50)
            $Button.FlatAppearance.BorderSize = 1
            $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(35, 35, 34)
            $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(47, 45, 40)
        }
        default {
            $Button.BackColor = [System.Drawing.Color]::FromArgb(68, 64, 60)
            $Button.ForeColor = [System.Drawing.Color]::FromArgb(250, 250, 249)
            $Button.FlatAppearance.BorderSize = 0
            $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(87, 83, 78)
            $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(41, 37, 36)
        }
    }
}

function Open-DeskPurgeFolder {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Container) {
        Start-Process -FilePath explorer.exe -ArgumentList ('"{0}"' -f $Path) | Out-Null
    }
}

function Show-DeskPurgeDialog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Heading,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Question', 'Success')]
        [string]$Type = 'Info',

        [hashtable[]]$Details = @(),

        [string]$PrimaryButtonText = 'OK',
        [string]$SecondaryButtonText,

        [ValidateSet('OK', 'Yes')]
        [string]$PrimaryResult = 'OK',

        [switch]$PrimaryIsDanger,

        [string]$AuxiliaryButtonText,

        [scriptblock]$AuxiliaryButtonAction
    )

    Initialize-DeskPurgeGui

    $theme = Get-DeskPurgeDialogTheme -Type $Type
    $hasDetails = $Details.Count -gt 0
    $formWidth = 760
    $formHeight = if ($hasDetails) { 554 } else { 430 }
    $rootWidth = $formWidth - 2
    $rootHeight = $formHeight - 2
    $contentX = 32
    $contentWidth = $rootWidth - 64
    $surface = [System.Drawing.Color]::FromArgb(18, 18, 17)
    $panel = [System.Drawing.Color]::FromArgb(24, 24, 23)
    $card = [System.Drawing.Color]::FromArgb(31, 31, 30)
    $border = [System.Drawing.Color]::FromArgb(67, 63, 57)
    $divider = [System.Drawing.Color]::FromArgb(48, 45, 41)
    $text = [System.Drawing.Color]::FromArgb(250, 250, 249)
    $mutedText = [System.Drawing.Color]::FromArgb(168, 162, 158)
    $bodyText = [System.Drawing.Color]::FromArgb(214, 211, 205)
    $resultMap = @{
        OK = [System.Windows.Forms.DialogResult]::OK
        Yes = [System.Windows.Forms.DialogResult]::Yes
    }

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = $Title
    $form.ClientSize = [System.Drawing.Size]::new($formWidth, $formHeight)
    $form.MinimumSize = [System.Drawing.Size]::new($formWidth, $formHeight)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $true
    $form.TopMost = $true
    $form.BackColor = $border
    $form.Font = [System.Drawing.Font]::new('Segoe UI', 9)
    $form.KeyPreview = $true
    $cornerRadius = 18
    $cornerPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $cornerPath.AddArc(0, 0, $cornerRadius, $cornerRadius, 180, 90)
    $cornerPath.AddArc($formWidth - $cornerRadius - 1, 0, $cornerRadius, $cornerRadius, 270, 90)
    $cornerPath.AddArc($formWidth - $cornerRadius - 1, $formHeight - $cornerRadius - 1, $cornerRadius, $cornerRadius, 0, 90)
    $cornerPath.AddArc(0, $formHeight - $cornerRadius - 1, $cornerRadius, $cornerRadius, 90, 90)
    $cornerPath.CloseFigure()
    $form.Region = [System.Drawing.Region]::new($cornerPath)

    $rootPanel = [System.Windows.Forms.Panel]::new()
    $rootPanel.Location = [System.Drawing.Point]::new(1, 1)
    $rootPanel.Size = [System.Drawing.Size]::new($rootWidth, $rootHeight)
    $rootPanel.BackColor = $surface
    $form.Controls.Add($rootPanel)

    $titleBar = [System.Windows.Forms.Panel]::new()
    $titleBar.Location = [System.Drawing.Point]::new(0, 0)
    $titleBar.Size = [System.Drawing.Size]::new($rootWidth, 44)
    $titleBar.BackColor = $panel
    $rootPanel.Controls.Add($titleBar)
    Add-DeskPurgeDragRegion -Form $form -Control $titleBar

    $titleLabel = [System.Windows.Forms.Label]::new()
    $titleLabel.Location = [System.Drawing.Point]::new(20, 0)
    $titleLabel.Size = [System.Drawing.Size]::new(520, 44)
    $titleLabel.Text = 'DeskPurge'
    $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $titleLabel.Font = [System.Drawing.Font]::new('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = $mutedText
    $titleBar.Controls.Add($titleLabel)
    Add-DeskPurgeDragRegion -Form $form -Control $titleLabel

    $closeButton = [System.Windows.Forms.Button]::new()
    $closeButton.Location = [System.Drawing.Point]::new($rootWidth - 44, 0)
    $closeButton.Size = [System.Drawing.Size]::new(44, 44)
    $closeButton.Text = 'X'
    $closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $closeButton.FlatAppearance.BorderSize = 0
    $closeButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(47, 45, 40)
    $closeButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(67, 63, 57)
    $closeButton.BackColor = $panel
    $closeButton.ForeColor = $mutedText
    $closeButton.Font = [System.Drawing.Font]::new('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $closeButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $titleBar.Controls.Add($closeButton)

    $badgeLabel = [System.Windows.Forms.Label]::new()
    $badgeLabel.Location = [System.Drawing.Point]::new($contentX, 70)
    $badgeLabel.Size = [System.Drawing.Size]::new(96, 26)
    $badgeLabel.Text = $theme.BadgeText
    $badgeLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $badgeLabel.Font = [System.Drawing.Font]::new('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $badgeLabel.BackColor = $theme.BadgeBack
    $badgeLabel.ForeColor = $theme.Accent
    $rootPanel.Controls.Add($badgeLabel)

    $headingLabel = [System.Windows.Forms.Label]::new()
    $headingLabel.Location = [System.Drawing.Point]::new($contentX, 108)
    $headingLabel.Size = [System.Drawing.Size]::new($contentWidth, 34)
    $headingLabel.Text = $Heading
    $headingLabel.Font = [System.Drawing.Font]::new('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    $headingLabel.ForeColor = $text
    $rootPanel.Controls.Add($headingLabel)

    $messageHeight = if ($hasDetails) { 56 } else { 180 }
    $messageLabel = [System.Windows.Forms.Label]::new()
    $messageLabel.Location = [System.Drawing.Point]::new($contentX, 148)
    $messageLabel.Size = [System.Drawing.Size]::new($contentWidth, $messageHeight)
    $messageLabel.Text = $Message
    $messageLabel.Font = [System.Drawing.Font]::new('Segoe UI', 9)
    $messageLabel.ForeColor = $bodyText
    $messageLabel.BackColor = $surface
    $rootPanel.Controls.Add($messageLabel)

    if ($hasDetails) {
        $detailsPanelHeight = [Math]::Max(168, [Math]::Min(250, ($Details.Count * 38) + 28))
        $detailsPanel = [System.Windows.Forms.Panel]::new()
        $detailsPanel.Location = [System.Drawing.Point]::new($contentX, 224)
        $detailsPanel.Size = [System.Drawing.Size]::new($contentWidth, $detailsPanelHeight)
        $detailsPanel.BackColor = $card
        $rootPanel.Controls.Add($detailsPanel)

        $accentStrip = [System.Windows.Forms.Panel]::new()
        $accentStrip.Location = [System.Drawing.Point]::new(0, 0)
        $accentStrip.Size = [System.Drawing.Size]::new(3, $detailsPanelHeight)
        $accentStrip.BackColor = $theme.AccentStrong
        $detailsPanel.Controls.Add($accentStrip)

        $detailY = 16
        $rowIndex = 0
        foreach ($detail in $Details) {
            $label = [System.Windows.Forms.Label]::new()
            $label.Location = [System.Drawing.Point]::new(22, $detailY + 3)
            $label.Size = [System.Drawing.Size]::new(112, 24)
            $label.Text = [string]$detail.Label
            $label.Font = [System.Drawing.Font]::new('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
            $label.ForeColor = $mutedText
            $label.BackColor = $card
            $detailsPanel.Controls.Add($label)

            $valueBox = [System.Windows.Forms.TextBox]::new()
            $valueBox.Location = [System.Drawing.Point]::new(142, $detailY)
            $valueBox.Size = [System.Drawing.Size]::new($contentWidth - 166, 24)
            $valueBox.Text = [string]$detail.Value
            $valueBox.ReadOnly = $true
            $valueBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
            $valueBox.BackColor = $card
            $valueBox.ForeColor = $text
            $valueBox.Font = [System.Drawing.Font]::new('Consolas', 9)
            $detailsPanel.Controls.Add($valueBox)

            if ($rowIndex -lt ($Details.Count - 1)) {
                $rowDivider = [System.Windows.Forms.Panel]::new()
                $rowDivider.Location = [System.Drawing.Point]::new(22, $detailY + 31)
                $rowDivider.Size = [System.Drawing.Size]::new($contentWidth - 44, 1)
                $rowDivider.BackColor = $divider
                $detailsPanel.Controls.Add($rowDivider)
            }

            $detailY += 38
            $rowIndex++
        }
    }

    $accentLine = [System.Windows.Forms.Panel]::new()
    $accentLine.Location = [System.Drawing.Point]::new($contentX, $rootHeight - 86)
    $accentLine.Size = [System.Drawing.Size]::new($contentWidth, 1)
    $accentLine.BackColor = $divider
    $rootPanel.Controls.Add($accentLine)

    $buttonPanel = [System.Windows.Forms.FlowLayoutPanel]::new()
    $buttonPanel.Location = [System.Drawing.Point]::new($contentX, $rootHeight - 64)
    $buttonPanel.Size = [System.Drawing.Size]::new($contentWidth, 40)
    $buttonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $buttonPanel.WrapContents = $false
    $buttonPanel.BackColor = $surface
    $rootPanel.Controls.Add($buttonPanel)

    $primaryButton = [System.Windows.Forms.Button]::new()
    $primaryButton.Text = $PrimaryButtonText
    $primaryButton.DialogResult = $resultMap[$PrimaryResult]
    Set-DeskPurgeButtonStyle -Button $primaryButton -Variant $(if ($PrimaryIsDanger) { 'Danger' } else { 'Primary' })
    $buttonPanel.Controls.Add($primaryButton)

    $secondaryButton = $null
    if (-not [string]::IsNullOrWhiteSpace($SecondaryButtonText)) {
        $secondaryButton = [System.Windows.Forms.Button]::new()
        $secondaryButton.Text = $SecondaryButtonText
        $secondaryButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        Set-DeskPurgeButtonStyle -Button $secondaryButton -Variant 'Secondary'
        $buttonPanel.Controls.Add($secondaryButton)
        $form.CancelButton = $secondaryButton
    }

    if (-not [string]::IsNullOrWhiteSpace($AuxiliaryButtonText) -and $null -ne $AuxiliaryButtonAction) {
        $auxiliaryButton = [System.Windows.Forms.Button]::new()
        $auxiliaryButton.Text = $AuxiliaryButtonText
        Set-DeskPurgeButtonStyle -Button $auxiliaryButton -Variant 'Quiet'
        if ($AuxiliaryButtonText.Length -gt 14) {
            $auxiliaryButton.Width = 184
        }
        $auxiliaryButton.Add_Click({
            try {
                $form.TopMost = $false
                & $AuxiliaryButtonAction
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Could not open the folder.`n`n$($_.Exception.Message)",
                    "Open Folder Failed",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
            }
        })
        $buttonPanel.Controls.Add($auxiliaryButton)
    }

    $closeButton.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($SecondaryButtonText)) {
            $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        }
        else {
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        }
        $form.Close()
    })

    $form.Add_KeyDown({
        param($sender, $eventArgs)

        if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            if (-not [string]::IsNullOrWhiteSpace($SecondaryButtonText)) {
                $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            }
            else {
                $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            }
            $form.Close()
        }
    })

    if (-not $PrimaryIsDanger) {
        $form.AcceptButton = $primaryButton
    }
    elseif ($null -ne $secondaryButton) {
        $form.Add_Shown({ $secondaryButton.Focus() })
    }

    try {
        return $form.ShowDialog()
    }
    finally {
        $form.Dispose()
    }
}

function Show-Popup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [ValidateSet('Info', 'Warning', 'Error', 'Question')]
        [string]$Type
    )

    $primaryText = 'OK'
    $secondaryText = $null
    $primaryResult = 'OK'
    if ($Type -eq 'Question') {
        $primaryText = 'Yes'
        $secondaryText = 'Cancel'
        $primaryResult = 'Yes'
    }

    $result = Show-DeskPurgeDialog `
        -Title $Title `
        -Heading $Title `
        -Message $Message `
        -Type $Type `
        -PrimaryButtonText $primaryText `
        -SecondaryButtonText $secondaryText `
        -PrimaryResult $primaryResult

    if ($Type -eq 'Error') { 
        exit 1 
    }
    return $result
}

function Show-DeleteConfirmation {
    param(
        [Parameter(Mandatory = $true)][string]$FolderToDelete,
        [Parameter(Mandatory = $true)][string]$FolderSizeDisplay,
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$ProtectedBoundary
    )

    $details = @(
        @{ Label = 'Folder'; Value = $FolderToDelete }
        @{ Label = 'Size'; Value = $FolderSizeDisplay }
        @{ Label = 'Shortcut'; Value = $ShortcutPath }
        @{ Label = 'Target app'; Value = $TargetPath }
        @{ Label = 'Boundary'; Value = $ProtectedBoundary }
    )

    return Show-DeskPurgeDialog `
        -Title 'Confirm Permanent Delete' `
        -Heading 'Delete this game folder?' `
        -Message 'DeskPurge found the install folder for this shortcut. Review the target carefully before continuing. This permanently deletes the folder, then removes the shortcut.' `
        -Type 'Question' `
        -Details $details `
        -PrimaryButtonText 'Delete folder' `
        -SecondaryButtonText 'Cancel' `
        -PrimaryResult 'Yes' `
        -PrimaryIsDanger `
        -AuxiliaryButtonText 'Open Folder' `
        -AuxiliaryButtonAction ({ Open-DeskPurgeFolder -Path $FolderToDelete }.GetNewClosure())
}

function Show-CompletionSummary {
    param(
        [Parameter(Mandatory = $true)][string]$FolderToDelete,
        [Parameter(Mandatory = $true)][string]$FolderSizeDisplay,
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$LogFile,
        [Parameter(Mandatory = $true)][bool]$ShortcutDeletedSuccessfully,
        [string]$ShortcutDeletionError
    )

    if ($ShortcutDeletedSuccessfully) {
        $containingFolder = Split-Path -Path $FolderToDelete -Parent
        $details = @(
            @{ Label = 'Folder'; Value = $FolderToDelete }
            @{ Label = 'Shortcut'; Value = $ShortcutPath }
            @{ Label = 'Freed'; Value = $FolderSizeDisplay }
            @{ Label = 'Log'; Value = $LogFile }
        )

        Show-DeskPurgeDialog `
            -Title 'DeskPurge Complete' `
            -Heading 'Game folder removed' `
            -Message 'DeskPurge removed the install folder and shortcut.' `
            -Type 'Success' `
            -Details $details `
            -PrimaryButtonText 'Done' `
            -AuxiliaryButtonText 'Open Containing Folder' `
            -AuxiliaryButtonAction ({ Open-DeskPurgeFolder -Path $containingFolder }.GetNewClosure()) | Out-Null
        return
    }

    $containingFolder = Split-Path -Path $FolderToDelete -Parent
    $details = @(
        @{ Label = 'Folder'; Value = $FolderToDelete }
        @{ Label = 'Shortcut'; Value = $ShortcutPath }
        @{ Label = 'Freed'; Value = $FolderSizeDisplay }
        @{ Label = 'Reason'; Value = $ShortcutDeletionError }
        @{ Label = 'Log'; Value = $LogFile }
    )

    Show-DeskPurgeDialog `
        -Title 'Shortcut Cleanup Needed' `
        -Heading 'Folder removed, shortcut still present' `
        -Message 'The game folder was deleted successfully, but DeskPurge could not remove the shortcut. You can delete the shortcut manually.' `
        -Type 'Warning' `
        -Details $details `
        -PrimaryButtonText 'Done' `
        -AuxiliaryButtonText 'Open Containing Folder' `
        -AuxiliaryButtonAction ({ Open-DeskPurgeFolder -Path $containingFolder }.GetNewClosure()) | Out-Null
}

# --- Main Script Logic ---
$ErrorActionPreference = 'Stop' # Default error action

if ([string]::IsNullOrWhiteSpace($LinkPathFromContextMenu)) {
    Show-Popup -Message "Script was called without a shortcut path. Intended for context menu use." -Title "Usage Error" -Type "Error"
}

$finalLinkPath = $LinkPathFromContextMenu
$targetExeName = $null
$targetPath = $null # Declare $targetPath here to use it later

try {
    # 1. Resolve Shortcut
    if (-not (Test-Path -LiteralPath $finalLinkPath -PathType Leaf) -or -not ($finalLinkPath.ToLowerInvariant().EndsWith(".lnk"))) {
        Show-Popup -Message "The provided item is not a valid shortcut (.lnk) file:`n$finalLinkPath" -Title "Invalid File" -Type "Error"
    }

    $shell = $null; $shortcut = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($finalLinkPath)
        $targetPath = $shortcut.TargetPath # Assign to $targetPath
        if ([string]::IsNullOrWhiteSpace($targetPath)) {
            Show-Popup -Message "Could not find the target application for this shortcut:`n$finalLinkPath" -Title "Target Not Found" -Type "Error"
        }
        $targetExeName = Split-Path -Path $targetPath -Leaf
    }
    finally {
        if ($null -ne $shortcut) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) | Out-Null }
        if ($null -ne $shell) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null }
    }

    if (-not (Test-Path -LiteralPath $targetPath)) {
        Show-Popup -Message "The target application path no longer exists:`n$targetPath" -Title "Target Missing" -Type "Error"
    }

    # 2. Determine the initial folder (immediate parent of the target)
    $initialFolderCandidate = Split-Path -Path $targetPath -Parent
    if ([string]::IsNullOrWhiteSpace($initialFolderCandidate) -or -not (Test-Path -LiteralPath $initialFolderCandidate -PathType Container)) {
        Show-Popup -Message "Could not determine a valid initial parent folder for target:`n$targetPath" -Title "Folder Error" -Type "Error"
    }

    # --- System-level protected paths (always active) ---
    $systemProtectedPaths = @(
        'c:\windows', 'c:\program files', 'c:\program files (x86)',
        "$([Environment]::GetFolderPath('UserProfile').TrimEnd('\').TrimEnd('/').ToLowerInvariant())",
        "$([Environment]::GetFolderPath('CommonDesktopDirectory').TrimEnd('\').TrimEnd('/').ToLowerInvariant())",
        "$([Environment]::GetFolderPath('Desktop').TrimEnd('\').TrimEnd('/').ToLowerInvariant())"
    )
    # --- User-defined game library folders (from config file) ---
    try {
        $userProtectedGameFolders = Get-ProtectedGameFolders -ConfigFile $ProtectedFoldersConfigFile
    }
    catch {
        Show-Popup -Message "DeskPurge needs at least one protected game-library folder before it can delete anything.`n`nConfig file:`n$ProtectedFoldersConfigFile`n`nWhat to do:`nOpen DeskPurge_ProtectedFolders.txt and add your actual game library root, such as D:\Games.`n`nTechnical detail:`n$($_.Exception.Message)`n`nNo deletion was attempted." -Title "Setup Needed" -Type "Error"
    }

    # 3. Traverse upwards to find the true game installation folder to delete
    Write-Host "DEBUG: Initial folder candidate: $initialFolderCandidate"
    $folderToDelete = Resolve-DeskPurgeDeletionTarget -InitialFolder $initialFolderCandidate -SystemProtectedPaths $systemProtectedPaths -UserProtectedFolders $userProtectedGameFolders
    Write-Host "DEBUG: Final folder determined for deletion: $folderToDelete"

    # 4. Final Safety Checks on the *determined* $folderToDelete
    $normalizedFolderToDelete = ConvertTo-DeskPurgeNormalizedPath -Path $folderToDelete
    if (Test-DeskPurgeRootDrive -Path $normalizedFolderToDelete) { Show-Popup -Message "DeskPurge selected a root drive as the deletion target, so it stopped immediately.`n`nBlocked target:`n$folderToDelete`n`nNo deletion was attempted." -Title "Deletion Blocked" -Type "Error" }
    if ($systemProtectedPaths -contains $normalizedFolderToDelete) { Show-Popup -Message "DeskPurge selected a protected system folder as the deletion target, so it stopped immediately.`n`nBlocked target:`n$folderToDelete`n`nNo deletion was attempted." -Title "Deletion Blocked" -Type "Error" }
    if ($userProtectedGameFolders -contains $normalizedFolderToDelete) { Show-Popup -Message "DeskPurge selected one of your protected game-library folders as the deletion target, so it stopped immediately.`n`nBlocked target:`n$folderToDelete`n`nNo deletion was attempted." -Title "Deletion Blocked" -Type "Error" }
    if (-not (Test-Path -LiteralPath $folderToDelete -PathType Container)) { Show-Popup -Message "DeskPurge could not verify the final folder to delete.`n`nTarget:`n$folderToDelete`n`nNo deletion was attempted." -Title "Invalid Delete Target" -Type "Error" }

    # --- Calculate Folder Size for Confirmation ---
    $folderSizeDisplay = Get-DeskPurgeFolderSizeDisplay -Path $folderToDelete

    # 5. Confirmation
    $protectedBoundary = Split-Path -Path $folderToDelete -Parent
    $userResponse = Show-DeleteConfirmation -FolderToDelete $folderToDelete -FolderSizeDisplay $folderSizeDisplay -ShortcutPath $finalLinkPath -TargetPath $targetPath -ProtectedBoundary $protectedBoundary
    if ($userResponse -ne [System.Windows.Forms.DialogResult]::Yes) { Write-Host "DEBUG: User cancelled. Exiting."; exit 0 }

    # --- NEW: Check if the target executable is running ---
    if ($targetExeName) {
        Write-Host "DEBUG: Checking if process '$targetExeName' is running..."
        # Remove .exe for Get-Process Name parameter if it exists
        $processNameToFind = $targetExeName.Replace(".exe", "")
        try {
            $runningProcesses = Get-Process -Name $processNameToFind -ErrorAction SilentlyContinue # SilentlyContinue to handle "not found"
            if ($runningProcesses) {
                # Further check if any of the found processes match the full $targetPath
                $gameProcessIsRunning = $false
                foreach ($proc in $runningProcesses) {
                    if ($proc.Path -eq $targetPath) {
                        $gameProcessIsRunning = $true
                        break
                    }
                }
                if ($gameProcessIsRunning) {
                    Show-Popup -Message "DeskPurge found the target app running from the folder it was about to delete.`n`nRunning app:`n$targetExeName`n`nPath:`n$targetPath`n`nClose the app and run DeskPurge again. No deletion was attempted." -Title "Application In Use" -Type "Error"
                    # This 'Error' type popup will cause the script to exit due to exit 1
                }
            }
        } catch {
            # Catch potential errors from Get-Process itself, though ErrorAction SilentlyContinue should prevent most
            Write-Warning "An error occurred while checking for running processes: $($_.Exception.Message)"
        }
        Write-Host "DEBUG: Process check complete. '$targetExeName' not found running from the target path."
    }
    # --- END NEW PROCESS CHECK ---

    # 6. Perform Deletion (Folder first, then shortcut)
    $logEntries = New-Object System.Collections.Generic.List[string]
    $folderDeletedSuccessfully = $false
    $shortcutDeletedSuccessfully = $false
    $shortcutDeletionError = $null

    try {
        Write-Host "DEBUG: Attempting to delete folder: $folderToDelete"
        Remove-Item -LiteralPath $folderToDelete -Recurse -Force
        $logEntries.Add("Deleted folder: $folderToDelete (Size: $folderSizeDisplay)")
        $folderDeletedSuccessfully = $true
        Write-Host "DEBUG: Folder deleted successfully."
    }
    catch [System.IO.IOException] { # Catch specific IO errors, often due to locked files
        $errorMessage = $_.Exception.Message
        Write-Host "ERROR deleting folder (IO Exception): $errorMessage"
        $customMessage = "DeskPurge could not delete the folder because Windows reported that one or more files may be in use.`n`nFolder:`n$folderToDelete`n`nClose the game, launcher, mod manager, or any related tools, then try again.`n`nTechnical detail:`n$errorMessage`n`nThe shortcut was not deleted."
        Show-Popup -Message $customMessage -Title "Folder Still In Use" -Type "Error" 
        # This 'Error' type popup will cause the script to exit
    }
    catch { # Catch any other errors during folder deletion
        $errorMessage = $_.Exception.Message
        Write-Host "ERROR deleting folder (General Exception): $errorMessage"
        Show-Popup -Message "DeskPurge could not delete the folder.`n`nFolder:`n$folderToDelete`n`nTechnical detail:`n$errorMessage`n`nThe shortcut was not deleted." -Title "Folder Delete Failed" -Type "Error"
        # This 'Error' type popup will cause the script to exit
    }

    # Only delete shortcut if folder deletion was successful
    if ($folderDeletedSuccessfully) {
        try {
            Write-Host "DEBUG: Attempting to delete shortcut: $finalLinkPath"
            Remove-Item -LiteralPath $finalLinkPath -Force
            $logEntries.Add("Deleted shortcut: $finalLinkPath")
            $shortcutDeletedSuccessfully = $true
            Write-Host "DEBUG: Shortcut deleted successfully."
        }
        catch {
            $shortcutDeletionError = $_.Exception.Message
            $errorMessage = "Failed to delete shortcut '$finalLinkPath' (folder was already deleted): $shortcutDeletionError"
            $logEntries.Add("WARNING: $errorMessage") # Log as warning as main task (folder) succeeded
        }
    } else {
        # This block should not be reached if the catches above for folder deletion use "Error" type popups which exit.
        # However, as a safeguard:
        Write-Host "INFO: Folder was not deleted, so shortcut will not be deleted either."
        $logEntries.Add("INFO: Folder deletion failed or was aborted. Shortcut '$finalLinkPath' was not deleted.")
    }
    

    # 7. Log
    $logFile   = Join-Path $PSScriptRoot "DeskPurge_Log.txt"
    $timestamp = Get-Date -Format 'yyyy-MM-dd hh:mm tt'
    # Only log if some action was attempted (i.e., user confirmed Yes)
    if ($logEntries.Count -gt 0) {
        $newBlock  = @(
        "[$timestamp]"
        $logEntries
        "---"
        )
        if (Test-Path $logFile) {
            $oldLines = Get-Content $logFile -Encoding UTF8
            $newBlock | Out-File -FilePath $logFile -Encoding UTF8
            $oldLines | Out-File -FilePath $logFile -Encoding UTF8 -Append
        } else {
            $newBlock | Out-File -FilePath $logFile -Encoding UTF8
        }
        if ($folderDeletedSuccessfully) {
            Show-CompletionSummary -FolderToDelete $folderToDelete -FolderSizeDisplay $folderSizeDisplay -ShortcutPath $finalLinkPath -LogFile $logFile -ShortcutDeletedSuccessfully $shortcutDeletedSuccessfully -ShortcutDeletionError $shortcutDeletionError
        }
    } # Else, if user cancelled before any action, no log/completion message needed beyond exiting.

}
catch { # Catch-all for any other unhandled script errors
    Show-Popup -Message "DeskPurge hit an unexpected script error before it could finish cleanly.`n`nTechnical detail:`n$($_.Exception.ToString())" -Title "Unexpected Error" -Type "Error"
}
