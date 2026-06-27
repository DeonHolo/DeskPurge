# DeskPurge.ps1
param(
    [switch]$NoQueue,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ShortcutPaths
)

$ErrorActionPreference = 'Stop'

$ConfigFileName = "DeskPurge_ProtectedFolders.txt"
$ScriptPath = $PSScriptRoot
$ProtectedFoldersConfigFile = Join-Path -Path $ScriptPath -ChildPath $ConfigFileName
. (Join-Path -Path $PSScriptRoot -ChildPath "DeskPurge.Core.ps1")

$script:DeskPurgeBatchGuiInitialized = $false
$script:DeskPurgeBatchAutoMinimizeSuppressedHandles = [System.Collections.Generic.HashSet[string]]::new()

function Initialize-DeskPurgeBatchGui {
    try {
        if (-not $script:DeskPurgeBatchGuiInitialized) {
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
            $script:DeskPurgeBatchGuiInitialized = $true
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

function Get-DeskPurgeBatchPalette {
    return @{
        Surface = [System.Drawing.Color]::FromArgb(18, 18, 17)
        Panel = [System.Drawing.Color]::FromArgb(24, 24, 23)
        Card = [System.Drawing.Color]::FromArgb(31, 31, 30)
        Border = [System.Drawing.Color]::FromArgb(67, 63, 57)
        Divider = [System.Drawing.Color]::FromArgb(48, 45, 41)
        Text = [System.Drawing.Color]::FromArgb(250, 250, 249)
        BodyText = [System.Drawing.Color]::FromArgb(214, 211, 205)
        MutedText = [System.Drawing.Color]::FromArgb(168, 162, 158)
        Danger = [System.Drawing.Color]::FromArgb(220, 38, 38)
        DangerHover = [System.Drawing.Color]::FromArgb(239, 68, 68)
        DangerDown = [System.Drawing.Color]::FromArgb(153, 27, 27)
        Warning = [System.Drawing.Color]::FromArgb(251, 191, 36)
        Success = [System.Drawing.Color]::FromArgb(74, 222, 128)
        Info = [System.Drawing.Color]::FromArgb(148, 163, 184)
    }
}

function Add-DeskPurgeBatchDragRegion {
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

function Set-DeskPurgeBatchAutoMinimizeSuppressed {
    param(
        [Parameter(Mandatory = $true)]$Form,
        [Parameter(Mandatory = $true)][bool]$Suppressed
    )

    if ($null -eq $Form -or $Form.IsDisposed) {
        return
    }

    $handleKey = $Form.Handle.ToString()
    if ($Suppressed) {
        $script:DeskPurgeBatchAutoMinimizeSuppressedHandles.Add($handleKey) | Out-Null
    }
    else {
        $script:DeskPurgeBatchAutoMinimizeSuppressedHandles.Remove($handleKey) | Out-Null
    }
}

function Set-DeskPurgeBatchButtonStyle {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Button]$Button,
        [ValidateSet('Primary', 'Secondary', 'Danger', 'Quiet')]
        [string]$Variant = 'Primary'
    )

    $palette = Get-DeskPurgeBatchPalette
    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.Font = [System.Drawing.Font]::new('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $Button.Height = 40
    $Button.Width = 144
    $Button.Margin = [System.Windows.Forms.Padding]::new(8, 0, 0, 0)
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand

    switch ($Variant) {
        'Danger' {
            $Button.BackColor = $palette.Danger
            $Button.ForeColor = [System.Drawing.Color]::White
            $Button.FlatAppearance.BorderSize = 0
            $Button.FlatAppearance.MouseOverBackColor = $palette.DangerHover
            $Button.FlatAppearance.MouseDownBackColor = $palette.DangerDown
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
            $Button.BackColor = $palette.Panel
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

function New-DeskPurgeBatchBaseForm {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [int]$Width = 1120,
        [int]$Height = 720,
        $Owner = $null,
        [bool]$AutoMinimizeOnDeactivate = $true,
        [bool]$ShowInTaskbar = $true,
        [bool]$TopMost = $true
    )

    Initialize-DeskPurgeBatchGui

    $palette = Get-DeskPurgeBatchPalette
    $form = [System.Windows.Forms.Form]::new()
    $form.Text = $Title
    $form.ClientSize = [System.Drawing.Size]::new($Width, $Height)
    $form.MinimumSize = [System.Drawing.Size]::new($Width, $Height)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    if ($null -ne $Owner) {
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    }
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.MaximizeBox = $false
    $form.MinimizeBox = $true
    $form.ShowInTaskbar = $ShowInTaskbar
    $form.TopMost = $TopMost
    $form.BackColor = $palette.Border
    $form.Font = [System.Drawing.Font]::new('Segoe UI', 9)
    $form.KeyPreview = $true

    $cornerRadius = 18
    $cornerPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $cornerPath.AddArc(0, 0, $cornerRadius, $cornerRadius, 180, 90)
    $cornerPath.AddArc($Width - $cornerRadius - 1, 0, $cornerRadius, $cornerRadius, 270, 90)
    $cornerPath.AddArc($Width - $cornerRadius - 1, $Height - $cornerRadius - 1, $cornerRadius, $cornerRadius, 0, 90)
    $cornerPath.AddArc(0, $Height - $cornerRadius - 1, $cornerRadius, $cornerRadius, 90, 90)
    $cornerPath.CloseFigure()
    $form.Region = [System.Drawing.Region]::new($cornerPath)

    $rootPanel = [System.Windows.Forms.Panel]::new()
    $rootPanel.Location = [System.Drawing.Point]::new(1, 1)
    $rootPanel.Size = [System.Drawing.Size]::new($Width - 2, $Height - 2)
    $rootPanel.BackColor = $palette.Surface
    $rootPanel.Tag = $palette
    $form.Controls.Add($rootPanel)

    $titleBar = [System.Windows.Forms.Panel]::new()
    $titleBar.Location = [System.Drawing.Point]::new(0, 0)
    $titleBar.Size = [System.Drawing.Size]::new($Width - 2, 44)
    $titleBar.BackColor = $palette.Panel
    $rootPanel.Controls.Add($titleBar)
    Add-DeskPurgeBatchDragRegion -Form $form -Control $titleBar

    $titleLabel = [System.Windows.Forms.Label]::new()
    $titleLabel.Location = [System.Drawing.Point]::new(20, 0)
    $titleLabel.Size = [System.Drawing.Size]::new($Width - 116, 44)
    $titleLabel.Text = 'DeskPurge'
    $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $titleLabel.Font = [System.Drawing.Font]::new('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = $palette.MutedText
    $titleBar.Controls.Add($titleLabel)
    Add-DeskPurgeBatchDragRegion -Form $form -Control $titleLabel

    $minimizeButton = [System.Windows.Forms.Button]::new()
    $minimizeButton.Location = [System.Drawing.Point]::new($Width - 90, 0)
    $minimizeButton.Size = [System.Drawing.Size]::new(44, 44)
    $minimizeButton.Text = [char]0x2014
    $minimizeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $minimizeButton.FlatAppearance.BorderSize = 0
    $minimizeButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(47, 45, 40)
    $minimizeButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(67, 63, 57)
    $minimizeButton.BackColor = $palette.Panel
    $minimizeButton.ForeColor = $palette.MutedText
    $minimizeButton.Font = [System.Drawing.Font]::new('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $minimizeButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $titleBar.Controls.Add($minimizeButton)
    $minimizeButton.Add_Click({
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
    })

    $closeButton = [System.Windows.Forms.Button]::new()
    $closeButton.Location = [System.Drawing.Point]::new($Width - 46, 0)
    $closeButton.Size = [System.Drawing.Size]::new(44, 44)
    $closeButton.Text = 'X'
    $closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $closeButton.FlatAppearance.BorderSize = 0
    $closeButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(47, 45, 40)
    $closeButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(67, 63, 57)
    $closeButton.BackColor = $palette.Panel
    $closeButton.ForeColor = $palette.MutedText
    $closeButton.Font = [System.Drawing.Font]::new('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $closeButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $titleBar.Controls.Add($closeButton)
    $closeButton.Add_Click({
        $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Close()
    })

    $form.Add_KeyDown({
        param($sender, $eventArgs)

        if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $form.Close()
        }
    })
    if ($AutoMinimizeOnDeactivate) {
        $form.Add_Deactivate({
            $handleKey = $form.Handle.ToString()
            if ($script:DeskPurgeBatchAutoMinimizeSuppressedHandles.Contains($handleKey)) {
                return
            }

            if ($form.Visible -and -not $form.IsDisposed -and $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) {
                $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
            }
        })
    }
    $form.Add_FormClosed({
        if ($null -ne $form -and $form.IsHandleCreated) {
            $script:DeskPurgeBatchAutoMinimizeSuppressedHandles.Remove($form.Handle.ToString()) | Out-Null
        }
    })

    return [pscustomobject]@{
        Form = $form
        Root = $rootPanel
        Palette = $palette
        Owner = $Owner
    }
}

function Show-DeskPurgeBatchMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Heading,
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Type = 'Info'
    )

    $base = New-DeskPurgeBatchBaseForm -Title $Title -Width 760 -Height 430
    $form = $base.Form
    $rootPanel = $base.Root
    $palette = $base.Palette
    $accent = switch ($Type) {
        'Error' { $palette.Danger }
        'Warning' { $palette.Warning }
        default { $palette.Info }
    }
    $badgeBack = switch ($Type) {
        'Error' { [System.Drawing.Color]::FromArgb(69, 10, 10) }
        'Warning' { [System.Drawing.Color]::FromArgb(69, 26, 3) }
        default { [System.Drawing.Color]::FromArgb(30, 41, 59) }
    }

    $badgeLabel = [System.Windows.Forms.Label]::new()
    $badgeLabel.Location = [System.Drawing.Point]::new(32, 70)
    $badgeLabel.Size = [System.Drawing.Size]::new(96, 26)
    $badgeLabel.Text = $Type.ToUpperInvariant()
    $badgeLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $badgeLabel.Font = [System.Drawing.Font]::new('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $badgeLabel.BackColor = $badgeBack
    $badgeLabel.ForeColor = $accent
    $rootPanel.Controls.Add($badgeLabel)

    $headingLabel = [System.Windows.Forms.Label]::new()
    $headingLabel.Location = [System.Drawing.Point]::new(32, 108)
    $headingLabel.Size = [System.Drawing.Size]::new(696, 34)
    $headingLabel.Text = $Heading
    $headingLabel.Font = [System.Drawing.Font]::new('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    $headingLabel.ForeColor = $palette.Text
    $rootPanel.Controls.Add($headingLabel)

    $messageLabel = [System.Windows.Forms.Label]::new()
    $messageLabel.Location = [System.Drawing.Point]::new(32, 152)
    $messageLabel.Size = [System.Drawing.Size]::new(696, 170)
    $messageLabel.Text = $Message
    $messageLabel.Font = [System.Drawing.Font]::new('Segoe UI', 9)
    $messageLabel.ForeColor = $palette.BodyText
    $messageLabel.BackColor = $palette.Surface
    $rootPanel.Controls.Add($messageLabel)

    $okButton = [System.Windows.Forms.Button]::new()
    $okButton.Text = 'OK'
    Set-DeskPurgeBatchButtonStyle -Button $okButton -Variant 'Primary'
    $okButton.Location = [System.Drawing.Point]::new(584, 366)
    $okButton.Add_Click({
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $rootPanel.Controls.Add($okButton)
    $form.AcceptButton = $okButton

    try {
        $form.ShowDialog() | Out-Null
    }
    finally {
        $form.Dispose()
    }
}

function Show-DeskPurgeBatchConfirmation {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Heading,
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$ConfirmText = 'Remove',
        [string]$CancelText = 'Cancel',
        $Owner = $null
    )

    $base = New-DeskPurgeBatchBaseForm `
        -Title $Title `
        -Width 620 `
        -Height 330 `
        -Owner $Owner `
        -AutoMinimizeOnDeactivate $false `
        -ShowInTaskbar $false `
        -TopMost $false
    $form = $base.Form
    $rootPanel = $base.Root
    $palette = $base.Palette

    $contentX = 32
    $contentWidth = 556

    $headingLabel = [System.Windows.Forms.Label]::new()
    $headingLabel.Location = [System.Drawing.Point]::new($contentX, 76)
    $headingLabel.Size = [System.Drawing.Size]::new($contentWidth, 34)
    $headingLabel.Text = $Heading
    $headingLabel.Font = [System.Drawing.Font]::new('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    $headingLabel.ForeColor = $palette.Text
    $rootPanel.Controls.Add($headingLabel)

    $messageBox = [System.Windows.Forms.TextBox]::new()
    $messageBox.Location = [System.Drawing.Point]::new($contentX, 124)
    $messageBox.Size = [System.Drawing.Size]::new($contentWidth, 102)
    $messageBox.Multiline = $true
    $messageBox.ReadOnly = $true
    $messageBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $messageBox.BackColor = $palette.Surface
    $messageBox.ForeColor = $palette.BodyText
    $messageBox.Font = [System.Drawing.Font]::new('Segoe UI', 9)
    $messageBox.Text = $Message
    $rootPanel.Controls.Add($messageBox)

    $divider = [System.Windows.Forms.Panel]::new()
    $divider.Location = [System.Drawing.Point]::new($contentX, 246)
    $divider.Size = [System.Drawing.Size]::new($contentWidth, 1)
    $divider.BackColor = $palette.Divider
    $rootPanel.Controls.Add($divider)

    $cancelButton = [System.Windows.Forms.Button]::new()
    $cancelButton.Location = [System.Drawing.Point]::new(290, 266)
    $cancelButton.Text = $CancelText
    Set-DeskPurgeBatchButtonStyle -Button $cancelButton -Variant 'Secondary'
    $cancelButton.Add_Click({
        $form.Tag = $false
        $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Close()
    })
    $rootPanel.Controls.Add($cancelButton)

    $confirmButton = [System.Windows.Forms.Button]::new()
    $confirmButton.Location = [System.Drawing.Point]::new(444, 266)
    $confirmButton.Text = $ConfirmText
    Set-DeskPurgeBatchButtonStyle -Button $confirmButton -Variant 'Danger'
    $confirmButton.Add_Click({
        $form.Tag = $true
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $rootPanel.Controls.Add($confirmButton)

    $form.AcceptButton = $confirmButton
    $form.CancelButton = $cancelButton
    $form.Tag = $false

    try {
        if ($null -ne $Owner) {
            $form.ShowDialog($Owner) | Out-Null
        }
        else {
            $form.ShowDialog() | Out-Null
        }

        return [bool]$form.Tag
    }
    finally {
        $form.Dispose()
    }
}

function Get-DeskPurgeBatchQueuePaths {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $queueKey = ($identity.User.Value -replace '[^a-zA-Z0-9]', '_')
    $queueDirectory = Join-Path -Path $env:TEMP -ChildPath 'DeskPurge'

    return [pscustomobject]@{
        Key = $queueKey
        Directory = $queueDirectory
        QueueFile = Join-Path -Path $queueDirectory -ChildPath "BatchQueue_$queueKey.txt"
        MarkerFile = Join-Path -Path $queueDirectory -ChildPath "BatchQueue_$queueKey.owner"
        MutexName = "Local\DeskPurgeBatchQueue_$queueKey"
    }
}

function Add-DeskPurgeBatchQueue {
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    $state = Get-DeskPurgeBatchQueuePaths
    $mutex = [System.Threading.Mutex]::new($false, $state.MutexName)
    $hasHandle = $false

    try {
        $hasHandle = $mutex.WaitOne(10000)
        if (-not $hasHandle) {
            throw "Timed out waiting for the DeskPurge batch queue."
        }

        New-Item -Path $state.Directory -ItemType Directory -Force | Out-Null
        foreach ($path in (Get-DeskPurgeUniqueShortcutPaths -Paths $Paths)) {
            Add-Content -LiteralPath $state.QueueFile -Value $path -Encoding UTF8
        }

        $shouldOpen = $false
        $markerIsStale = $false
        if (Test-Path -LiteralPath $state.MarkerFile -PathType Leaf) {
            $markerAge = (Get-Date) - (Get-Item -LiteralPath $state.MarkerFile).LastWriteTime
            $markerIsStale = $markerAge.TotalSeconds -gt 20
        }

        if ((-not (Test-Path -LiteralPath $state.MarkerFile -PathType Leaf)) -or $markerIsStale) {
            Set-Content -LiteralPath $state.MarkerFile -Value $PID -Encoding ASCII
            $shouldOpen = $true
        }

        return [pscustomobject]@{
            ShouldOpen = $shouldOpen
            State = $state
        }
    }
    finally {
        if ($hasHandle) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Read-DeskPurgeBatchQueue {
    param([Parameter(Mandatory = $true)]$State)

    $mutex = [System.Threading.Mutex]::new($false, $State.MutexName)
    $hasHandle = $false

    try {
        $hasHandle = $mutex.WaitOne(10000)
        if (-not $hasHandle) {
            throw "Timed out reading the DeskPurge batch queue."
        }

        $queuedPaths = @()
        if (Test-Path -LiteralPath $State.QueueFile -PathType Leaf) {
            $queuedPaths = Get-Content -LiteralPath $State.QueueFile -Encoding UTF8
            Remove-Item -LiteralPath $State.QueueFile -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $State.MarkerFile -PathType Leaf) {
            Remove-Item -LiteralPath $State.MarkerFile -Force -ErrorAction SilentlyContinue
        }

        return Get-DeskPurgeUniqueShortcutPaths -Paths $queuedPaths
    }
    finally {
        if ($hasHandle) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function New-DeskPurgeBatchErrorPlan {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Message
    )

    return [pscustomobject]@{
        ShortcutPath = $ShortcutPath
        ShortcutName = Split-Path -Path $ShortcutPath -Leaf
        TargetPath = $null
        FolderToDelete = $null
        FolderSizeBytes = $null
        FolderSizeDisplay = 'N/A'
        ProtectedBoundary = $null
        LargeFolderWarning = $false
        LargeFolderWarningMessage = $null
        Status = $Status
        Message = $Message
    }
}

function New-DeskPurgeBatchLoadingPlan {
    param([Parameter(Mandatory = $true)][string]$ShortcutPath)

    return [pscustomobject]@{
        ShortcutPath = $ShortcutPath
        ShortcutName = Split-Path -Path $ShortcutPath -Leaf
        TargetPath = $null
        FolderToDelete = $null
        FolderSizeBytes = $null
        FolderSizeDisplay = '...'
        ProtectedBoundary = $null
        LargeFolderWarning = $false
        LargeFolderWarningMessage = $null
        Status = 'Resolving'
        Message = 'Resolving shortcut and install folder.'
    }
}

function Get-DeskPurgeProtectedFolderSetupCandidates {
    param([Parameter(Mandatory = $true)][string[]]$ShortcutPaths)

    $candidatesByPath = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $shell = $null

    try {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($shortcutPath in (Get-DeskPurgeUniqueShortcutPaths -Paths $ShortcutPaths)) {
            if ([string]::IsNullOrWhiteSpace($shortcutPath) -or -not $shortcutPath.ToLowerInvariant().EndsWith('.lnk')) {
                continue
            }
            if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
                continue
            }

            $shortcut = $null
            try {
                $shortcut = $shell.CreateShortcut($shortcutPath)
                foreach ($candidate in (Get-DeskPurgeProtectedFolderCandidatesFromTargetPath -TargetPath $shortcut.TargetPath)) {
                    Add-DeskPurgeProtectedFolderCandidate `
                        -CandidatesByPath $candidatesByPath `
                        -Path $candidate.Path `
                        -Source $candidate.Source
                }
            }
            catch {
                continue
            }
            finally {
                if ($null -ne $shortcut) {
                    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) | Out-Null
                }
            }
        }
    }
    catch {
        # Fall through to common-folder detection below.
    }
    finally {
        if ($null -ne $shell) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        }
    }

    foreach ($commonPath in (Get-DeskPurgeCommonProtectedFolderCandidatePaths)) {
        Add-DeskPurgeProtectedFolderCandidate `
            -CandidatesByPath $candidatesByPath `
            -Path $commonPath `
            -Source 'Existing common game-library folder'
    }

    return @($candidatesByPath.Values | Sort-Object Path)
}

function Save-DeskPurgeProtectedFoldersConfig {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigFile,
        [Parameter(Mandatory = $true)][string[]]$ProtectedFolderPaths
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $configLines = @(
        '# DeskPurge Protected Folders Configuration'
        '#'
        "# Generated by DeskPurge setup on $timestamp."
        '# These folders are stop boundaries. DeskPurge deletes the game folder below one of these boundaries.'
        '# Review these paths before each destructive cleanup if you move your game libraries.'
        ''
        '# Confirmed game library boundaries:'
    ) + $ProtectedFolderPaths

    $configLines | Set-Content -LiteralPath $ConfigFile -Encoding UTF8
}

function Add-DeskPurgeProtectedFolderConfigEntry {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigFile,
        [Parameter(Mandatory = $true)][string]$FolderPath,
        [string]$Comment = 'Added by DeskPurge protected folders.'
    )

    $normalizedFolderPath = ConvertTo-DeskPurgeNormalizedPath -Path $FolderPath
    if (-not $normalizedFolderPath) {
        throw "Protected folder path is empty."
    }

    if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
        Save-DeskPurgeProtectedFoldersConfig -ConfigFile $ConfigFile -ProtectedFolderPaths @($FolderPath)
        return $true
    }

    $lines = @(Get-Content -LiteralPath $ConfigFile -Encoding UTF8)
    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith("#")) {
            continue
        }

        if ((ConvertTo-DeskPurgeNormalizedPath -Path $trimmedLine) -eq $normalizedFolderPath) {
            return $false
        }
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $linesToAdd = [System.Collections.Generic.List[string]]::new()
    $linesToAdd.Add('')
    if (-not [string]::IsNullOrWhiteSpace($Comment)) {
        $linesToAdd.Add("# $Comment $timestamp.")
    }
    $linesToAdd.Add($FolderPath)
    Add-Content -LiteralPath $ConfigFile -Encoding UTF8 -Value ([string[]]$linesToAdd.ToArray())
    return $true
}

function Test-DeskPurgeDriveAvailable {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path -match '^([a-zA-Z]):\\') {
        return $null -ne (Get-PSDrive -Name $matches[1] -PSProvider FileSystem -ErrorAction SilentlyContinue)
    }

    return $true
}

function Get-DeskPurgeProtectedFolderConfigEntries {
    param([Parameter(Mandatory = $true)][string]$ConfigFile)

    $entries = [System.Collections.Generic.List[object]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
        return @()
    }

    foreach ($rawLine in (Get-Content -LiteralPath $ConfigFile -Encoding UTF8)) {
        $path = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($path) -or $path.StartsWith('#')) {
            continue
        }

        $normalizedPath = ConvertTo-DeskPurgeNormalizedPath -Path $path
        if (-not $normalizedPath -or -not $seenPaths.Add($normalizedPath)) {
            continue
        }

        $status = if (Test-Path -LiteralPath $path -PathType Container) {
            'Found'
        }
        elseif (-not (Test-DeskPurgeDriveAvailable -Path $path)) {
            'Offline drive'
        }
        else {
            'Missing'
        }

        $entries.Add([pscustomobject]@{
            Path = $path
            NormalizedPath = $normalizedPath
            Status = $status
        })
    }

    return [object[]]$entries.ToArray()
}

function Remove-DeskPurgeProtectedFolderConfigEntry {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigFile,
        [Parameter(Mandatory = $true)][string]$FolderPath
    )

    $normalizedFolderPath = ConvertTo-DeskPurgeNormalizedPath -Path $FolderPath
    if (-not $normalizedFolderPath -or -not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
        return $false
    }

    $changed = $false
    $newLines = [System.Collections.Generic.List[string]]::new()
    foreach ($rawLine in (Get-Content -LiteralPath $ConfigFile -Encoding UTF8)) {
        $trimmedLine = $rawLine.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmedLine) -and
            -not $trimmedLine.StartsWith('#') -and
            (ConvertTo-DeskPurgeNormalizedPath -Path $trimmedLine) -eq $normalizedFolderPath) {
            $changed = $true
            continue
        }

        $newLines.Add($rawLine)
    }

    if ($changed) {
        $newLines | Set-Content -LiteralPath $ConfigFile -Encoding UTF8
    }

    return $changed
}

function Show-DeskPurgeProtectedFolderSetup {
    param(
        [Parameter(Mandatory = $true)][string[]]$ShortcutPaths,
        [Parameter(Mandatory = $true)][string]$ConfigFile,
        [Parameter(Mandatory = $true)][string]$SetupError
    )

    $candidates = @(Get-DeskPurgeProtectedFolderSetupCandidates -ShortcutPaths $ShortcutPaths)
    if ($candidates.Count -eq 0) {
        Show-DeskPurgeBatchMessage `
            -Title 'Setup Needed' `
            -Heading 'Protected folders are required' `
            -Message "DeskPurge needs at least one protected game-library folder before it can delete anything.`n`nConfig file:`n$ConfigFile`n`nTechnical detail:`n$SetupError`n`nNo candidates were detected automatically. Add your game library root to DeskPurge_ProtectedFolders.txt and run DeskPurge again." `
            -Type 'Error'
        return $false
    }

    $base = New-DeskPurgeBatchBaseForm -Title 'DeskPurge Setup' -Width 920 -Height 640
    $form = $base.Form
    $rootPanel = $base.Root
    $palette = $base.Palette
    $contentX = 32
    $contentWidth = 854

    $badgeLabel = [System.Windows.Forms.Label]::new()
    $badgeLabel.Location = [System.Drawing.Point]::new($contentX, 66)
    $badgeLabel.Size = [System.Drawing.Size]::new(104, 26)
    $badgeLabel.Text = 'SETUP'
    $badgeLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $badgeLabel.Font = [System.Drawing.Font]::new('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $badgeLabel.BackColor = [System.Drawing.Color]::FromArgb(69, 26, 3)
    $badgeLabel.ForeColor = $palette.Warning
    $rootPanel.Controls.Add($badgeLabel)

    $headingLabel = [System.Windows.Forms.Label]::new()
    $headingLabel.Location = [System.Drawing.Point]::new($contentX, 104)
    $headingLabel.Size = [System.Drawing.Size]::new($contentWidth, 34)
    $headingLabel.Text = 'Confirm protected folders'
    $headingLabel.Font = [System.Drawing.Font]::new('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    $headingLabel.ForeColor = $palette.Text
    $rootPanel.Controls.Add($headingLabel)

    $messageLabel = [System.Windows.Forms.Label]::new()
    $messageLabel.Location = [System.Drawing.Point]::new($contentX, 144)
    $messageLabel.Size = [System.Drawing.Size]::new($contentWidth, 48)
    $messageLabel.Text = 'DeskPurge needs stop boundaries before it can delete folders. Review the detected library roots, keep only paths that directly contain game folders, then save.'
    $messageLabel.Font = [System.Drawing.Font]::new('Segoe UI', 9)
    $messageLabel.ForeColor = $palette.BodyText
    $messageLabel.BackColor = $palette.Surface
    $rootPanel.Controls.Add($messageLabel)

    $grid = [System.Windows.Forms.DataGridView]::new()
    $grid.Location = [System.Drawing.Point]::new($contentX, 206)
    $grid.Size = [System.Drawing.Size]::new($contentWidth, 306)
    Set-DeskPurgeBatchGridStyle -Grid $grid
    $rootPanel.Controls.Add($grid)

    $selectedColumn = [System.Windows.Forms.DataGridViewCheckBoxColumn]::new()
    $selectedColumn.Name = 'Selected'
    $selectedColumn.HeaderText = ''
    $selectedColumn.Width = 42
    $grid.Columns.Add($selectedColumn) | Out-Null

    foreach ($column in @(
        @{ Name = 'Folder'; Text = 'Protected folder'; Width = 452 },
        @{ Name = 'Source'; Text = 'Detected from'; Width = 350 }
    )) {
        $textColumn = [System.Windows.Forms.DataGridViewTextBoxColumn]::new()
        $textColumn.Name = $column.Name
        $textColumn.HeaderText = $column.Text
        $textColumn.Width = $column.Width
        $textColumn.ReadOnly = $true
        $grid.Columns.Add($textColumn) | Out-Null
    }

    foreach ($candidate in $candidates) {
        $rowIndex = $grid.Rows.Add($true, $candidate.Path, $candidate.Source)
        $grid.Rows[$rowIndex].Tag = $candidate
    }

    $summaryLabel = [System.Windows.Forms.Label]::new()
    $summaryLabel.Location = [System.Drawing.Point]::new($contentX, 526)
    $summaryLabel.Size = [System.Drawing.Size]::new(600, 24)
    $summaryLabel.Font = [System.Drawing.Font]::new('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $summaryLabel.ForeColor = $palette.MutedText
    $summaryLabel.BackColor = $palette.Surface
    $rootPanel.Controls.Add($summaryLabel)

    $divider = [System.Windows.Forms.Panel]::new()
    $divider.Location = [System.Drawing.Point]::new($contentX, 554)
    $divider.Size = [System.Drawing.Size]::new($contentWidth, 1)
    $divider.BackColor = $palette.Divider
    $rootPanel.Controls.Add($divider)

    $buttonPanel = [System.Windows.Forms.FlowLayoutPanel]::new()
    $buttonPanel.Location = [System.Drawing.Point]::new($contentX, 576)
    $buttonPanel.Size = [System.Drawing.Size]::new($contentWidth, 40)
    $buttonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $buttonPanel.WrapContents = $false
    $buttonPanel.BackColor = $palette.Surface
    $rootPanel.Controls.Add($buttonPanel)

    $saveButton = [System.Windows.Forms.Button]::new()
    $saveButton.Text = 'Save folders'
    Set-DeskPurgeBatchButtonStyle -Button $saveButton -Variant 'Primary'
    $buttonPanel.Controls.Add($saveButton)

    $cancelButton = [System.Windows.Forms.Button]::new()
    $cancelButton.Text = 'Cancel'
    Set-DeskPurgeBatchButtonStyle -Button $cancelButton -Variant 'Secondary'
    $buttonPanel.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    function Update-DeskPurgeProtectedFolderSetupSummary {
        $selectedCount = 0
        foreach ($row in $grid.Rows) {
            if ([bool]$row.Cells['Selected'].Value) {
                $selectedCount++
            }
        }

        $summaryLabel.Text = "$selectedCount protected folder(s) selected"
        $saveButton.Enabled = $selectedCount -gt 0
    }

    $grid.Add_CurrentCellDirtyStateChanged({
        if ($grid.IsCurrentCellDirty) {
            $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) | Out-Null
        }
    })
    $grid.Add_CellValueChanged({ Update-DeskPurgeProtectedFolderSetupSummary })

    $cancelButton.Add_Click({
        $form.Tag = $false
        $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Close()
    })

    $saveButton.Add_Click({
        $selectedPaths = [System.Collections.Generic.List[string]]::new()
        foreach ($row in $grid.Rows) {
            if ([bool]$row.Cells['Selected'].Value) {
                $selectedPaths.Add([string]$row.Cells['Folder'].Value)
            }
        }

        try {
            Save-DeskPurgeProtectedFoldersConfig -ConfigFile $ConfigFile -ProtectedFolderPaths ([string[]]$selectedPaths.ToArray())
            $form.Tag = $true
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not save protected folders.`n`n$($_.Exception.Message)",
                "Save Failed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    $form.Tag = $false
    Update-DeskPurgeProtectedFolderSetupSummary

    try {
        $form.ShowDialog() | Out-Null
        return [bool]$form.Tag
    }
    finally {
        $form.Dispose()
    }
}

function Get-DeskPurgeBatchResolutionContext {
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    $systemProtectedPaths = Get-DeskPurgeSystemProtectedPaths
    try {
        $userProtectedGameFolders = Get-ProtectedGameFolders -ConfigFile $ProtectedFoldersConfigFile
    }
    catch {
        $setupCompleted = Show-DeskPurgeProtectedFolderSetup `
            -ShortcutPaths $Paths `
            -ConfigFile $ProtectedFoldersConfigFile `
            -SetupError $_.Exception.Message

        if (-not $setupCompleted) {
            exit 1
        }

        try {
            $userProtectedGameFolders = Get-ProtectedGameFolders -ConfigFile $ProtectedFoldersConfigFile
        }
        catch {
            Show-DeskPurgeBatchMessage `
                -Title 'Setup Needed' `
                -Heading 'Protected folders are required' `
                -Message "DeskPurge still could not load protected folders after setup.`n`nConfig file:`n$ProtectedFoldersConfigFile`n`nTechnical detail:`n$($_.Exception.Message)`n`nNo deletion was attempted." `
                -Type 'Error'
            exit 1
        }
    }

    return [pscustomobject]@{
        SystemProtectedPaths = [string[]]$systemProtectedPaths
        UserProtectedGameFolders = [string[]]$userProtectedGameFolders
        IsElevated = [bool](Test-DeskPurgeCurrentProcessElevated)
    }
}

function Resolve-DeskPurgeBatchPlans {
    param(
        [Parameter(Mandatory = $true)][string[]]$Paths,
        [object]$ResolutionContext = $null
    )

    if ($null -eq $ResolutionContext) {
        $ResolutionContext = Get-DeskPurgeBatchResolutionContext -Paths $Paths
    }

    $systemProtectedPaths = [string[]]$ResolutionContext.SystemProtectedPaths
    $userProtectedGameFolders = [string[]]$ResolutionContext.UserProtectedGameFolders
    $isElevated = [bool]$ResolutionContext.IsElevated

    $plans = [System.Collections.Generic.List[object]]::new()
    $shell = $null

    try {
        $shell = New-Object -ComObject WScript.Shell

        foreach ($path in (Get-DeskPurgeUniqueShortcutPaths -Paths $Paths)) {
            if ([string]::IsNullOrWhiteSpace($path)) {
                continue
            }

            if (-not $path.ToLowerInvariant().EndsWith('.lnk')) {
                $plans.Add((New-DeskPurgeBatchErrorPlan -ShortcutPath $path -Status 'Error' -Message 'Not a shortcut (.lnk) file.'))
                continue
            }

            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                $plans.Add((New-DeskPurgeBatchErrorPlan -ShortcutPath $path -Status 'Error' -Message 'Shortcut file no longer exists.'))
                continue
            }

            $shortcut = $null
            try {
                $shortcut = $shell.CreateShortcut($path)
                $targetPath = $shortcut.TargetPath
                $plan = New-DeskPurgeShortcutPlan `
                    -ShortcutPath $path `
                    -TargetPath $targetPath `
                    -SystemProtectedPaths $systemProtectedPaths `
                    -UserProtectedFolders $userProtectedGameFolders `
                    -IsElevated $isElevated
                $plans.Add($plan)
            }
            catch {
                $plans.Add((New-DeskPurgeBatchErrorPlan -ShortcutPath $path -Status 'Error' -Message $_.Exception.Message))
            }
            finally {
                if ($null -ne $shortcut) {
                    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) | Out-Null
                }
            }
        }
    }
    finally {
        if ($null -ne $shell) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        }
    }

    return [object[]]$plans.ToArray()
}

function Get-DeskPurgeBatchShortcutResolutionInputs {
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    $inputs = [System.Collections.Generic.List[object]]::new()
    $uniquePaths = @(Get-DeskPurgeUniqueShortcutPaths -Paths $Paths)
    $shell = $null

    try {
        $shell = New-Object -ComObject WScript.Shell
    }
    catch {
        foreach ($path in $uniquePaths) {
            [void]$inputs.Add([pscustomobject]@{
                ShortcutPath = $path
                TargetPath = $null
                Status = 'Error'
                Message = "Could not start shortcut resolver: $($_.Exception.Message)"
            })
        }

        return [object[]]$inputs.ToArray()
    }

    try {
        foreach ($path in $uniquePaths) {
            if ([string]::IsNullOrWhiteSpace($path)) {
                continue
            }

            if (-not $path.ToLowerInvariant().EndsWith('.lnk')) {
                [void]$inputs.Add([pscustomobject]@{
                    ShortcutPath = $path
                    TargetPath = $null
                    Status = 'Error'
                    Message = 'Not a shortcut (.lnk) file.'
                })
                continue
            }

            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                [void]$inputs.Add([pscustomobject]@{
                    ShortcutPath = $path
                    TargetPath = $null
                    Status = 'Error'
                    Message = 'Shortcut file no longer exists.'
                })
                continue
            }

            $shortcut = $null
            try {
                $shortcut = $shell.CreateShortcut($path)
                [void]$inputs.Add([pscustomobject]@{
                    ShortcutPath = $path
                    TargetPath = $shortcut.TargetPath
                    Status = 'Pending'
                    Message = $null
                })
            }
            catch {
                [void]$inputs.Add([pscustomobject]@{
                    ShortcutPath = $path
                    TargetPath = $null
                    Status = 'Error'
                    Message = $_.Exception.Message
                })
            }
            finally {
                if ($null -ne $shortcut) {
                    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) | Out-Null
                }
            }
        }
    }
    finally {
        if ($null -ne $shell) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        }
    }

    return [object[]]$inputs.ToArray()
}

function Start-DeskPurgeBatchPlanResolutionJob {
    param(
        [Parameter(Mandatory = $true)][string[]]$Paths,
        [Parameter(Mandatory = $true)]$ResolutionContext
    )

    $separator = [string][char]30
    $fieldSeparator = [string][char]31
    $coreScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'DeskPurge.Core.ps1'
    $resolutionInputs = @(Get-DeskPurgeBatchShortcutResolutionInputs -Paths $Paths)
    $inputsPayload = ($resolutionInputs | ForEach-Object {
        @(
            [string]$_.ShortcutPath,
            [string]$_.TargetPath,
            [string]$_.Status,
            [string]$_.Message
        ) -join $fieldSeparator
    }) -join $separator
    $systemProtectedPayload = ([string[]]$ResolutionContext.SystemProtectedPaths) -join $separator
    $userProtectedPayload = ([string[]]$ResolutionContext.UserProtectedGameFolders) -join $separator
    $isElevated = [bool]$ResolutionContext.IsElevated

    $scriptBlock = {
        param(
            [string]$CoreScriptPath,
            [string]$InputsPayload,
            [string]$SystemProtectedPayload,
            [string]$UserProtectedPayload,
            [bool]$IsElevated,
            [string]$Separator,
            [string]$FieldSeparator
        )

        $ErrorActionPreference = 'Stop'
        . $CoreScriptPath

        function ConvertFrom-DeskPurgeJobPayload {
            param([AllowNull()][string]$Payload)

            if ([string]::IsNullOrEmpty($Payload)) {
                return [string[]]@()
            }

            return [string[]]($Payload -split [regex]::Escape($Separator))
        }

        function ConvertFrom-DeskPurgeJobInputPayload {
            param([AllowNull()][string]$Payload)

            $inputs = [System.Collections.Generic.List[object]]::new()
            if ([string]::IsNullOrEmpty($Payload)) {
                return [object[]]$inputs.ToArray()
            }

            foreach ($record in ($Payload -split [regex]::Escape($Separator))) {
                if ([string]::IsNullOrWhiteSpace($record)) {
                    continue
                }

                $fields = $record -split [regex]::Escape($FieldSeparator), 4
                [void]$inputs.Add([pscustomobject]@{
                    ShortcutPath = if ($fields.Count -gt 0) { $fields[0] } else { $null }
                    TargetPath = if ($fields.Count -gt 1) { $fields[1] } else { $null }
                    Status = if ($fields.Count -gt 2) { $fields[2] } else { 'Error' }
                    Message = if ($fields.Count -gt 3) { $fields[3] } else { 'Shortcut resolution input was incomplete.' }
                })
            }

            return [object[]]$inputs.ToArray()
        }

        function New-DeskPurgeBatchJobErrorPlan {
            param(
                [Parameter(Mandatory = $true)][string]$ShortcutPath,
                [Parameter(Mandatory = $true)][string]$Status,
                [Parameter(Mandatory = $true)][string]$Message
            )

            return [pscustomobject]@{
                ShortcutPath = $ShortcutPath
                ShortcutName = Split-Path -Path $ShortcutPath -Leaf
                TargetPath = $null
                FolderToDelete = $null
                FolderSizeBytes = $null
                FolderSizeDisplay = 'N/A'
                ProtectedBoundary = $null
                LargeFolderWarning = $false
                LargeFolderWarningMessage = $null
                Status = $Status
                Message = $Message
            }
        }

        $resolutionInputs = ConvertFrom-DeskPurgeJobInputPayload -Payload $InputsPayload
        $systemProtectedPaths = ConvertFrom-DeskPurgeJobPayload -Payload $SystemProtectedPayload
        $userProtectedFolders = ConvertFrom-DeskPurgeJobPayload -Payload $UserProtectedPayload

        foreach ($resolutionInput in $resolutionInputs) {
            try {
                $path = $resolutionInput.ShortcutPath
                if ([string]::IsNullOrWhiteSpace($path)) {
                    continue
                }

                if ($resolutionInput.Status -ne 'Pending') {
                    Write-Output (New-DeskPurgeBatchJobErrorPlan -ShortcutPath $path -Status $resolutionInput.Status -Message $resolutionInput.Message)
                    continue
                }

                $plan = New-DeskPurgeShortcutPlan `
                    -ShortcutPath $path `
                    -TargetPath $resolutionInput.TargetPath `
                    -SystemProtectedPaths $systemProtectedPaths `
                    -UserProtectedFolders $userProtectedFolders `
                    -IsElevated $IsElevated
                Write-Output $plan
            }
            catch {
                Write-Output (New-DeskPurgeBatchJobErrorPlan -ShortcutPath $resolutionInput.ShortcutPath -Status 'Error' -Message $_.Exception.Message)
            }
        }
    }

    return Start-Job `
        -Name "DeskPurgeResolve_$PID" `
        -ScriptBlock $scriptBlock `
        -ArgumentList $coreScriptPath, $inputsPayload, $systemProtectedPayload, $userProtectedPayload, $isElevated, $separator, $fieldSeparator
}

function Set-DeskPurgeBatchGridStyle {
    param([Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$Grid)

    $palette = Get-DeskPurgeBatchPalette
    $Grid.BackgroundColor = $palette.Card
    $Grid.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $Grid.EnableHeadersVisualStyles = $false
    $Grid.GridColor = $palette.Divider
    $Grid.RowHeadersVisible = $false
    $Grid.AllowUserToAddRows = $false
    $Grid.AllowUserToDeleteRows = $false
    $Grid.AllowUserToResizeColumns = $false
    $Grid.AllowUserToResizeRows = $false
    $Grid.MultiSelect = $false
    $Grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $Grid.AutoSizeRowsMode = [System.Windows.Forms.DataGridViewAutoSizeRowsMode]::None
    $Grid.ColumnHeadersHeight = 34
    $Grid.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
    $Grid.RowHeadersWidthSizeMode = [System.Windows.Forms.DataGridViewRowHeadersWidthSizeMode]::DisableResizing
    $Grid.ShowCellToolTips = $false
    $Grid.RowTemplate.Height = 32
    $Grid.ColumnHeadersDefaultCellStyle.BackColor = $palette.Panel
    $Grid.ColumnHeadersDefaultCellStyle.ForeColor = $palette.MutedText
    $Grid.ColumnHeadersDefaultCellStyle.Font = [System.Drawing.Font]::new('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
    $Grid.DefaultCellStyle.BackColor = $palette.Card
    $Grid.DefaultCellStyle.ForeColor = $palette.BodyText
    $Grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(58, 55, 50)
    $Grid.DefaultCellStyle.SelectionForeColor = $palette.Text
    $Grid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(27, 27, 26)
}

function Set-DeskPurgeBatchRowStatusStyle {
    param([Parameter(Mandatory = $true)][System.Windows.Forms.DataGridViewRow]$Row)

    $palette = Get-DeskPurgeBatchPalette
    $plan = $Row.Tag
    $statusCell = $Row.Cells['Status']

    $Row.DefaultCellStyle.ForeColor = $palette.BodyText
    foreach ($cell in $Row.Cells) {
        $cell.Style.ForeColor = $palette.BodyText
    }
    $Row.Cells['Selected'].ReadOnly = $false

    switch ($plan.Status) {
        'Ready' {
            if ([string]::IsNullOrWhiteSpace($plan.FolderToDelete)) {
                $statusCell.Style.ForeColor = $palette.Warning
            } else {
                $statusCell.Style.ForeColor = $palette.Success
            }
        }
        'Needs admin' {
            $statusCell.Style.ForeColor = $palette.Warning
        }
        'Resolving' {
            $statusCell.Style.ForeColor = $palette.Info
        }
        default {
            $statusCell.Style.ForeColor = $palette.Danger
        }
    }
    if ($plan.LargeFolderWarning -and $plan.Status -eq 'Ready') {
        $statusCell.Style.ForeColor = $palette.Warning
        $Row.Cells['Size'].Style.ForeColor = $palette.Warning
    }

    if ($plan.Status -ne 'Ready') {
        $Row.Cells['Selected'].ReadOnly = $true
        $Row.Cells['Selected'].Value = $false
        $Row.DefaultCellStyle.ForeColor = $palette.MutedText
    }
}

function Get-DeskPurgeStatusDisplay {
    param([Parameter(Mandatory = $true)]$Plan)

    if ($Plan.Status -eq 'Ready' -and $Plan.LargeFolderWarning) {
        return 'Large folder'
    }

    if ($Plan.Status -eq 'Ready' -and [string]::IsNullOrWhiteSpace($Plan.FolderToDelete)) {
        return 'Shortcut only'
    }

    return $Plan.Status
}

function Open-DeskPurgeBatchFolder {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Container) {
        Start-Process -FilePath explorer.exe -ArgumentList ('"{0}"' -f $Path) | Out-Null
    }
}

function Open-DeskPurgeProtectedFoldersConfig {
    param([Parameter(Mandatory = $true)][string]$ConfigFile)

    if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
        @(
            '# DeskPurge Protected Folders Configuration'
            '#'
            '# Add one protected game-library folder per line.'
        ) | Set-Content -LiteralPath $ConfigFile -Encoding UTF8
    }

    Start-Process -FilePath notepad.exe -ArgumentList ('"{0}"' -f $ConfigFile) | Out-Null
}

function Show-DeskPurgeProtectedFoldersManager {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigFile,
        $Owner = $null
    )

    $base = New-DeskPurgeBatchBaseForm `
        -Title 'DeskPurge Protected Folders' `
        -Width 920 `
        -Height 640 `
        -Owner $Owner `
        -AutoMinimizeOnDeactivate $false `
        -ShowInTaskbar $false `
        -TopMost $false
    $form = $base.Form
    $rootPanel = $base.Root
    $palette = $base.Palette
    $contentX = 32
    $contentWidth = 854

    $headingLabel = [System.Windows.Forms.Label]::new()
    $headingLabel.Location = [System.Drawing.Point]::new($contentX, 76)
    $headingLabel.Size = [System.Drawing.Size]::new($contentWidth, 34)
    $headingLabel.Text = 'Protected folders'
    $headingLabel.Font = [System.Drawing.Font]::new('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    $headingLabel.ForeColor = $palette.Text
    $rootPanel.Controls.Add($headingLabel)

    $messageLabel = [System.Windows.Forms.Label]::new()
    $messageLabel.Location = [System.Drawing.Point]::new($contentX, 116)
    $messageLabel.Size = [System.Drawing.Size]::new($contentWidth, 42)
    $messageLabel.Text = 'These folders are stop boundaries. DeskPurge deletes the game folder below one of these folders, never the boundary itself.'
    $messageLabel.Font = [System.Drawing.Font]::new('Segoe UI', 9)
    $messageLabel.ForeColor = $palette.BodyText
    $messageLabel.BackColor = $palette.Surface
    $rootPanel.Controls.Add($messageLabel)

    $grid = [System.Windows.Forms.DataGridView]::new()
    $grid.Location = [System.Drawing.Point]::new($contentX, 166)
    $grid.Size = [System.Drawing.Size]::new($contentWidth, 360)
    $grid.ReadOnly = $true
    $grid.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    Set-DeskPurgeBatchGridStyle -Grid $grid
    $rootPanel.Controls.Add($grid)

    foreach ($column in @(
        @{ Name = 'Folder'; Text = 'Protected folder'; MinimumWidth = 650; FillWeight = 82 },
        @{ Name = 'Status'; Text = 'Status'; Width = 150; MinimumWidth = 150 }
    )) {
        $textColumn = [System.Windows.Forms.DataGridViewTextBoxColumn]::new()
        $textColumn.Name = $column.Name
        $textColumn.HeaderText = $column.Text
        $textColumn.MinimumWidth = $column.MinimumWidth
        $textColumn.Resizable = [System.Windows.Forms.DataGridViewTriState]::False
        if ($column.ContainsKey('Width')) {
            $textColumn.Width = $column.Width
            $textColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None
        }
        else {
            $textColumn.FillWeight = $column.FillWeight
            $textColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
        }
        $textColumn.ReadOnly = $true
        $grid.Columns.Add($textColumn) | Out-Null
    }

    $summaryLabel = [System.Windows.Forms.Label]::new()
    $summaryLabel.Location = [System.Drawing.Point]::new($contentX, 540)
    $summaryLabel.Size = [System.Drawing.Size]::new(520, 24)
    $summaryLabel.Font = [System.Drawing.Font]::new('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $summaryLabel.ForeColor = $palette.MutedText
    $summaryLabel.BackColor = $palette.Surface
    $rootPanel.Controls.Add($summaryLabel)

    $divider = [System.Windows.Forms.Panel]::new()
    $divider.Location = [System.Drawing.Point]::new($contentX, 568)
    $divider.Size = [System.Drawing.Size]::new($contentWidth, 1)
    $divider.BackColor = $palette.Divider
    $rootPanel.Controls.Add($divider)

    $buttonPanel = [System.Windows.Forms.FlowLayoutPanel]::new()
    $buttonPanel.Location = [System.Drawing.Point]::new($contentX, 590)
    $buttonPanel.Size = [System.Drawing.Size]::new($contentWidth, 40)
    $buttonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $buttonPanel.WrapContents = $false
    $buttonPanel.BackColor = $palette.Surface
    $rootPanel.Controls.Add($buttonPanel)

    $doneButton = [System.Windows.Forms.Button]::new()
    $doneButton.Text = 'Done'
    Set-DeskPurgeBatchButtonStyle -Button $doneButton -Variant 'Primary'
    $buttonPanel.Controls.Add($doneButton)

    $openConfigButton = [System.Windows.Forms.Button]::new()
    $openConfigButton.Text = 'Open config'
    Set-DeskPurgeBatchButtonStyle -Button $openConfigButton -Variant 'Quiet'
    $buttonPanel.Controls.Add($openConfigButton)

    $openButton = [System.Windows.Forms.Button]::new()
    $openButton.Text = 'Open folder'
    Set-DeskPurgeBatchButtonStyle -Button $openButton -Variant 'Quiet'
    $buttonPanel.Controls.Add($openButton)

    $removeButton = [System.Windows.Forms.Button]::new()
    $removeButton.Text = 'Remove selected'
    $removeButton.Width = 160
    Set-DeskPurgeBatchButtonStyle -Button $removeButton -Variant 'Secondary'
    $buttonPanel.Controls.Add($removeButton)

    $addButton = [System.Windows.Forms.Button]::new()
    $addButton.Text = 'Add folder...'
    Set-DeskPurgeBatchButtonStyle -Button $addButton -Variant 'Secondary'
    $buttonPanel.Controls.Add($addButton)

    function Get-DeskPurgeSelectedProtectedFolderEntry {
        if ($null -eq $grid.CurrentRow) {
            return $null
        }

        return $grid.CurrentRow.Tag
    }

    function Update-DeskPurgeProtectedFoldersManagerActions {
        $entry = Get-DeskPurgeSelectedProtectedFolderEntry
        $removeButton.Enabled = $null -ne $entry
        $openButton.Enabled = $null -ne $entry -and $entry.Status -eq 'Found'
    }

    function Refresh-DeskPurgeProtectedFoldersManagerGrid {
        $grid.Rows.Clear()
        $entries = @(Get-DeskPurgeProtectedFolderConfigEntries -ConfigFile $ConfigFile)
        foreach ($entry in $entries) {
            $rowIndex = $grid.Rows.Add($entry.Path, $entry.Status)
            $row = $grid.Rows[$rowIndex]
            $row.Tag = $entry
            switch ($entry.Status) {
                'Found' { $row.Cells['Status'].Style.ForeColor = $palette.Success }
                'Offline drive' { $row.Cells['Status'].Style.ForeColor = $palette.Warning }
                default { $row.Cells['Status'].Style.ForeColor = $palette.Danger }
            }
        }

        $summaryLabel.Text = "$($entries.Count) protected folder(s)"
        Update-DeskPurgeProtectedFoldersManagerActions
    }

    $grid.Add_SelectionChanged({ Update-DeskPurgeProtectedFoldersManagerActions })

    $addButton.Add_Click({
        $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dialog.Description = 'Select a protected game-library folder'
        $dialog.ShowNewFolderButton = $false
        try {
            if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
                Add-DeskPurgeProtectedFolderConfigEntry `
                    -ConfigFile $ConfigFile `
                    -FolderPath $dialog.SelectedPath `
                    -Comment 'Added by DeskPurge protected folders on' | Out-Null
                $form.Tag.Changed = $true
                Refresh-DeskPurgeProtectedFoldersManagerGrid
            }
        }
        finally {
            $dialog.Dispose()
        }
    })

    $removeButton.Add_Click({
        $entry = Get-DeskPurgeSelectedProtectedFolderEntry
        if ($null -eq $entry) {
            return
        }

        $confirmed = Show-DeskPurgeBatchConfirmation `
            -Title 'Remove Protected Folder' `
            -Heading 'Remove this protected folder?' `
            -Message "$($entry.Path)`r`n`r`nDeskPurge may resolve deletion targets differently after this." `
            -ConfirmText 'Remove' `
            -CancelText 'Cancel' `
            -Owner $form
        if (-not $confirmed) {
            return
        }

        if (Remove-DeskPurgeProtectedFolderConfigEntry -ConfigFile $ConfigFile -FolderPath $entry.Path) {
            $form.Tag.Changed = $true
            Refresh-DeskPurgeProtectedFoldersManagerGrid
        }
    })

    $openButton.Add_Click({
        $entry = Get-DeskPurgeSelectedProtectedFolderEntry
        if ($null -eq $entry -or $entry.Status -ne 'Found') {
            return
        }

        try {
            $form.TopMost = $false
            Open-DeskPurgeBatchFolder -Path $entry.Path
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

    $openConfigButton.Add_Click({
        try {
            $form.TopMost = $false
            Open-DeskPurgeProtectedFoldersConfig -ConfigFile $ConfigFile
            $form.Tag.Changed = $true
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not open protected folders config.`n`n$($_.Exception.Message)",
                "Open Config Failed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    })

    $doneButton.Add_Click({
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.CancelButton = $doneButton
    $form.Tag = [pscustomobject]@{ Changed = $false }

    Refresh-DeskPurgeProtectedFoldersManagerGrid

    try {
        if ($null -ne $Owner) {
            $form.ShowDialog($Owner) | Out-Null
        }
        else {
            $form.ShowDialog() | Out-Null
        }
        return $form.Tag
    }
    finally {
        $form.Dispose()
    }
}

function Show-DeskPurgeSingleReview {
    param([Parameter(Mandatory = $true)]$Plan)

    $base = New-DeskPurgeBatchBaseForm -Title 'DeskPurge Uninstall' -Width 760 -Height 640
    $form = $base.Form
    $rootPanel = $base.Root
    $palette = $base.Palette
    $contentX = 32
    $contentWidth = 694
    $statusIsReady = $Plan.Status -eq 'Ready'
    $statusAccent = switch ($Plan.Status) {
        'Ready' { $palette.Success }
        'Needs admin' { $palette.Warning }
        default { $palette.Danger }
    }
    $badgeBack = switch ($Plan.Status) {
        'Ready' { [System.Drawing.Color]::FromArgb(5, 46, 22) }
        'Needs admin' { [System.Drawing.Color]::FromArgb(69, 26, 3) }
        default { [System.Drawing.Color]::FromArgb(69, 10, 10) }
    }

    $badgeLabel = [System.Windows.Forms.Label]::new()
    $badgeLabel.Location = [System.Drawing.Point]::new($contentX, 70)
    $badgeLabel.Size = [System.Drawing.Size]::new(96, 26)
    $badgeLabel.Text = $Plan.Status.ToUpperInvariant()
    $badgeLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $badgeLabel.Font = [System.Drawing.Font]::new('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $badgeLabel.BackColor = $badgeBack
    $badgeLabel.ForeColor = $statusAccent
    $rootPanel.Controls.Add($badgeLabel)

    $headingLabel = [System.Windows.Forms.Label]::new()
    $headingLabel.Location = [System.Drawing.Point]::new($contentX, 108)
    $headingLabel.Size = [System.Drawing.Size]::new($contentWidth, 34)
    $headingLabel.Text = 'Delete this game folder?'
    $headingLabel.Font = [System.Drawing.Font]::new('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    $headingLabel.ForeColor = $palette.Text
    $rootPanel.Controls.Add($headingLabel)

    $messageLabel = [System.Windows.Forms.Label]::new()
    $messageLabel.Location = [System.Drawing.Point]::new($contentX, 148)
    $messageLabel.Size = [System.Drawing.Size]::new($contentWidth, 52)
    $messageLabel.Text = if ($statusIsReady) {
        if ([string]::IsNullOrWhiteSpace($Plan.FolderToDelete)) {
            'DeskPurge found this shortcut has no existing target folder. Review the shortcut before continuing.'
        } else {
            'DeskPurge found the install folder for this shortcut. Review the target carefully before continuing.'
        }
    }
    else {
        "DeskPurge cannot delete this item yet: $($Plan.Message)"
    }
    $messageLabel.Font = [System.Drawing.Font]::new('Segoe UI', 9)
    $messageLabel.ForeColor = $palette.BodyText
    $messageLabel.BackColor = $palette.Surface
    $rootPanel.Controls.Add($messageLabel)

    $detailsPanel = [System.Windows.Forms.Panel]::new()
    $detailsPanel.Location = [System.Drawing.Point]::new($contentX, 224)
    $detailsPanel.Size = [System.Drawing.Size]::new($contentWidth, 250)
    $detailsPanel.BackColor = $palette.Card
    $rootPanel.Controls.Add($detailsPanel)

    $accentStrip = [System.Windows.Forms.Panel]::new()
    $accentStrip.Location = [System.Drawing.Point]::new(0, 0)
    $accentStrip.Size = [System.Drawing.Size]::new(3, 250)
    $accentStrip.BackColor = $statusAccent
    $detailsPanel.Controls.Add($accentStrip)

    $details = @(
        @{ Label = 'Folder'; Value = $Plan.FolderToDelete }
        @{ Label = 'Size'; Value = $Plan.FolderSizeDisplay }
        @{ Label = 'Shortcut'; Value = $Plan.ShortcutPath }
        @{ Label = 'Target app'; Value = $Plan.TargetPath }
        @{ Label = 'Boundary'; Value = $Plan.ProtectedBoundary }
        @{ Label = 'Details'; Value = if ($Plan.LargeFolderWarning) { $Plan.LargeFolderWarningMessage } else { $Plan.Message } }
    )

    $detailY = 16
    $rowIndex = 0
    foreach ($detail in $details) {
        $label = [System.Windows.Forms.Label]::new()
        $label.Location = [System.Drawing.Point]::new(22, $detailY + 3)
        $label.Size = [System.Drawing.Size]::new(112, 24)
        $label.Text = [string]$detail.Label
        $label.Font = [System.Drawing.Font]::new('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
        $label.ForeColor = $palette.MutedText
        $label.BackColor = $palette.Card
        $detailsPanel.Controls.Add($label)

        $valueBox = [System.Windows.Forms.TextBox]::new()
        $valueBox.Location = [System.Drawing.Point]::new(142, $detailY)
        $valueBox.Size = [System.Drawing.Size]::new($contentWidth - 166, 24)
        $valueBox.Text = [string]$detail.Value
        $valueBox.ReadOnly = $true
        $valueBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
        $valueBox.BackColor = $palette.Card
        $valueBox.ForeColor = $palette.Text
        $valueBox.Font = [System.Drawing.Font]::new('Consolas', 9)
        $detailsPanel.Controls.Add($valueBox)

        if ($rowIndex -lt ($details.Count - 1)) {
            $rowDivider = [System.Windows.Forms.Panel]::new()
            $rowDivider.Location = [System.Drawing.Point]::new(22, $detailY + 31)
            $rowDivider.Size = [System.Drawing.Size]::new($contentWidth - 44, 1)
            $rowDivider.BackColor = $palette.Divider
            $detailsPanel.Controls.Add($rowDivider)
        }

        $detailY += 38
        $rowIndex++
    }

    $divider = [System.Windows.Forms.Panel]::new()
    $divider.Location = [System.Drawing.Point]::new($contentX, 546)
    $divider.Size = [System.Drawing.Size]::new($contentWidth, 1)
    $divider.BackColor = $palette.Divider
    $rootPanel.Controls.Add($divider)

    $buttonPanel = [System.Windows.Forms.FlowLayoutPanel]::new()
    $buttonPanel.Location = [System.Drawing.Point]::new($contentX, 568)
    $buttonPanel.Size = [System.Drawing.Size]::new($contentWidth, 40)
    $buttonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $buttonPanel.WrapContents = $false
    $buttonPanel.BackColor = $palette.Surface
    $rootPanel.Controls.Add($buttonPanel)

    $deleteButton = [System.Windows.Forms.Button]::new()
    if ([string]::IsNullOrWhiteSpace($Plan.FolderToDelete)) {
        $deleteButton.Text = 'Delete shortcut'
    } else {
        $deleteButton.Text = 'Delete folder'
    }
    $deleteButton.Enabled = $statusIsReady
    Set-DeskPurgeBatchButtonStyle -Button $deleteButton -Variant 'Danger'
    $buttonPanel.Controls.Add($deleteButton)

    $cancelButton = [System.Windows.Forms.Button]::new()
    $cancelButton.Text = 'Cancel'
    Set-DeskPurgeBatchButtonStyle -Button $cancelButton -Variant 'Secondary'
    $buttonPanel.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    if ($Plan.Status -eq 'Needs admin' -and -not (Test-DeskPurgeCurrentProcessElevated)) {
        $restartButton = [System.Windows.Forms.Button]::new()
        $restartButton.Text = 'Restart as admin'
        $restartButton.Width = 156
        Set-DeskPurgeBatchButtonStyle -Button $restartButton -Variant 'Quiet'
        $buttonPanel.Controls.Add($restartButton)
        $restartButton.Add_Click({
            $form.Tag = [pscustomobject]@{ Action = 'Elevate'; Selected = @() }
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        })
    }

    if (-not [string]::IsNullOrWhiteSpace($Plan.FolderToDelete)) {
        $openButton = [System.Windows.Forms.Button]::new()
        $openButton.Text = 'Open Folder'
        Set-DeskPurgeBatchButtonStyle -Button $openButton -Variant 'Quiet'
        $buttonPanel.Controls.Add($openButton)
        $openButton.Add_Click({
            try {
                $form.TopMost = $false
                Open-DeskPurgeBatchFolder -Path $Plan.FolderToDelete
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
    }

    if ($Plan.LargeFolderWarning -and -not [string]::IsNullOrWhiteSpace($Plan.FolderToDelete)) {
        $protectButton = [System.Windows.Forms.Button]::new()
        $protectButton.Text = 'Protect this folder'
        $protectButton.Width = 172
        Set-DeskPurgeBatchButtonStyle -Button $protectButton -Variant 'Quiet'
        $buttonPanel.Controls.Add($protectButton)
        $protectButton.Add_Click({
            $form.Tag = [pscustomobject]@{
                Action = 'ProtectFolder'
                Selected = @()
                FolderToProtect = $Plan.FolderToDelete
            }
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        })
    }

    $cancelButton.Add_Click({
        $form.Tag = [pscustomobject]@{ Action = 'Cancel'; Selected = @() }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Close()
    })

    $deleteButton.Add_Click({
        $form.Tag = [pscustomobject]@{ Action = 'Delete'; Selected = [object[]]@($Plan) }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    $form.Tag = [pscustomobject]@{ Action = 'Cancel'; Selected = @() }

    try {
        $form.ShowDialog() | Out-Null
        return $form.Tag
    }
    finally {
        $form.Dispose()
    }
}

function Show-DeskPurgeBatchReview {
    param(
        [object[]]$Plans = $null,
        [string[]]$Paths = $null,
        [object]$ResolutionContext = $null
    )

    $streamPlans = $null -ne $Paths -and @($Paths).Count -gt 0
    if ($streamPlans) {
        $Plans = @(Get-DeskPurgeUniqueShortcutPaths -Paths $Paths | ForEach-Object {
            New-DeskPurgeBatchLoadingPlan -ShortcutPath $_
        })
    }
    else {
        $Plans = @($Plans)
    }

    $base = New-DeskPurgeBatchBaseForm -Title 'DeskPurge Uninstall'
    $form = $base.Form
    $rootPanel = $base.Root
    $palette = $base.Palette
    $contentX = 32
    $contentWidth = 1054

    $headingLabel = [System.Windows.Forms.Label]::new()
    $headingLabel.Location = [System.Drawing.Point]::new($contentX, 76)
    $headingLabel.Size = [System.Drawing.Size]::new($contentWidth, 34)
    $headingLabel.Text = 'Review selected shortcuts'
    $headingLabel.Font = [System.Drawing.Font]::new('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    $headingLabel.ForeColor = $palette.Text
    $rootPanel.Controls.Add($headingLabel)

    $messageLabel = [System.Windows.Forms.Label]::new()
    $messageLabel.Location = [System.Drawing.Point]::new($contentX, 116)
    $messageLabel.Size = [System.Drawing.Size]::new($contentWidth, 42)
    $messageLabel.Text = if ($streamPlans) {
        'DeskPurge is resolving these shortcuts into install folders. Only checked Ready rows will be permanently deleted.'
    }
    else {
        'DeskPurge resolved these shortcuts into install folders. Only checked Ready rows will be permanently deleted.'
    }
    $messageLabel.Font = [System.Drawing.Font]::new('Segoe UI', 9)
    $messageLabel.ForeColor = $palette.BodyText
    $messageLabel.BackColor = $palette.Surface
    $rootPanel.Controls.Add($messageLabel)

    $grid = [System.Windows.Forms.DataGridView]::new()
    $grid.Location = [System.Drawing.Point]::new($contentX, 166)
    $grid.Size = [System.Drawing.Size]::new($contentWidth, 390)
    $grid.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    Set-DeskPurgeBatchGridStyle -Grid $grid
    $rootPanel.Controls.Add($grid)

    $selectedColumn = [System.Windows.Forms.DataGridViewCheckBoxColumn]::new()
    $selectedColumn.Name = 'Selected'
    $selectedColumn.HeaderText = ''
    $selectedColumn.Width = 44
    $selectedColumn.MinimumWidth = 44
    $selectedColumn.Resizable = [System.Windows.Forms.DataGridViewTriState]::False
    $selectedColumn.Frozen = $true
    $selectedColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None
    $grid.Columns.Add($selectedColumn) | Out-Null

    foreach ($column in @(
        @{ Name = 'Status'; Text = 'Status'; Width = 112; MinimumWidth = 112 },
        @{ Name = 'Size'; Text = 'Size'; Width = 100; MinimumWidth = 100 },
        @{ Name = 'Shortcut'; Text = 'Shortcut'; MinimumWidth = 150; FillWeight = 20 },
        @{ Name = 'Folder'; Text = 'Folder to delete'; MinimumWidth = 240; FillWeight = 30 },
        @{ Name = 'Target'; Text = 'Target app'; MinimumWidth = 240; FillWeight = 30 },
        @{ Name = 'Boundary'; Text = 'Boundary'; MinimumWidth = 170; FillWeight = 20 }
    )) {
        $textColumn = [System.Windows.Forms.DataGridViewTextBoxColumn]::new()
        $textColumn.Name = $column.Name
        $textColumn.HeaderText = $column.Text
        $textColumn.MinimumWidth = $column.MinimumWidth
        $textColumn.Resizable = [System.Windows.Forms.DataGridViewTriState]::False
        if ($column.Name -eq 'Size') {
            $textColumn.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Programmatic
        }
        if ($column.ContainsKey('Width')) {
            $textColumn.Width = $column.Width
            $textColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None
        }
        else {
            $textColumn.FillWeight = $column.FillWeight
            $textColumn.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
        }
        $textColumn.ReadOnly = $true
        $grid.Columns.Add($textColumn) | Out-Null
    }

    $script:DeskPurgeSizeSortDirection = 'None'

    $rowsByShortcutPath = @{}

    function Set-DeskPurgeBatchReviewRowPlan {
        param(
            [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridViewRow]$Row,
            [Parameter(Mandatory = $true)]$Plan
        )

        $Row.Tag = $Plan
        $Row.Cells['Selected'].Value = ($Plan.Status -eq 'Ready')
        $Row.Cells['Status'].Value = Get-DeskPurgeStatusDisplay -Plan $Plan
        $Row.Cells['Size'].Value = $Plan.FolderSizeDisplay
        $Row.Cells['Shortcut'].Value = $Plan.ShortcutName
        $Row.Cells['Folder'].Value = $Plan.FolderToDelete
        $Row.Cells['Target'].Value = $Plan.TargetPath
        $Row.Cells['Boundary'].Value = $Plan.ProtectedBoundary
        Set-DeskPurgeBatchRowStatusStyle -Row $Row
    }

    foreach ($plan in $Plans) {
        $rowIndex = $grid.Rows.Add(
            ($plan.Status -eq 'Ready'),
            (Get-DeskPurgeStatusDisplay -Plan $plan),
            $plan.FolderSizeDisplay,
            $plan.ShortcutName,
            $plan.FolderToDelete,
            $plan.TargetPath,
            $plan.ProtectedBoundary
        )
        $row = $grid.Rows[$rowIndex]
        Set-DeskPurgeBatchReviewRowPlan -Row $row -Plan $plan
        $shortcutKey = ConvertTo-DeskPurgeNormalizedPath -Path $plan.ShortcutPath
        if ($shortcutKey) {
            $rowsByShortcutPath[$shortcutKey] = $row
        }
    }

    $warningPanel = [System.Windows.Forms.Panel]::new()
    $warningPanel.Location = [System.Drawing.Point]::new($contentX, 568)
    $warningPanel.Size = [System.Drawing.Size]::new($contentWidth, 28)
    $warningPanel.BackColor = [System.Drawing.Color]::FromArgb(69, 26, 3)
    $warningPanel.Visible = $false
    $rootPanel.Controls.Add($warningPanel)

    $warningLabel = [System.Windows.Forms.Label]::new()
    $warningLabel.Location = [System.Drawing.Point]::new(12, 0)
    $warningLabel.Size = [System.Drawing.Size]::new($contentWidth - 24, 28)
    $warningLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $warningLabel.Font = [System.Drawing.Font]::new('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
    $warningLabel.ForeColor = $palette.Warning
    $warningLabel.BackColor = $warningPanel.BackColor
    $warningPanel.Controls.Add($warningLabel)

    $summaryLabel = [System.Windows.Forms.Label]::new()
    $summaryLabel.Location = [System.Drawing.Point]::new($contentX, 606)
    $summaryLabel.Size = [System.Drawing.Size]::new(560, 24)
    $summaryLabel.Font = [System.Drawing.Font]::new('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $summaryLabel.ForeColor = $palette.MutedText
    $summaryLabel.BackColor = $palette.Surface
    $rootPanel.Controls.Add($summaryLabel)

    $divider = [System.Windows.Forms.Panel]::new()
    $divider.Location = [System.Drawing.Point]::new($contentX, 638)
    $divider.Size = [System.Drawing.Size]::new($contentWidth, 1)
    $divider.BackColor = $palette.Divider
    $rootPanel.Controls.Add($divider)

    $buttonPanel = [System.Windows.Forms.FlowLayoutPanel]::new()
    $buttonPanel.Location = [System.Drawing.Point]::new($contentX, 660)
    $buttonPanel.Size = [System.Drawing.Size]::new($contentWidth, 40)
    $buttonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $buttonPanel.WrapContents = $false
    $buttonPanel.BackColor = $palette.Surface
    $rootPanel.Controls.Add($buttonPanel)

    $deleteButton = [System.Windows.Forms.Button]::new()
    $deleteButton.Text = 'Delete selected'
    $deleteButton.Width = 156
    Set-DeskPurgeBatchButtonStyle -Button $deleteButton -Variant 'Danger'
    $buttonPanel.Controls.Add($deleteButton)

    $cancelButton = [System.Windows.Forms.Button]::new()
    $cancelButton.Text = 'Cancel'
    Set-DeskPurgeBatchButtonStyle -Button $cancelButton -Variant 'Secondary'
    $buttonPanel.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    $protectButton = [System.Windows.Forms.Button]::new()
    $protectButton.Text = 'Protect this folder'
    $protectButton.Width = 172
    $protectButton.Enabled = $false
    Set-DeskPurgeBatchButtonStyle -Button $protectButton -Variant 'Quiet'
    $buttonPanel.Controls.Add($protectButton)

    $openButton = [System.Windows.Forms.Button]::new()
    $openButton.Text = 'Open Folder'
    $openButton.Enabled = $false
    Set-DeskPurgeBatchButtonStyle -Button $openButton -Variant 'Quiet'
    $buttonPanel.Controls.Add($openButton)

    $configButton = [System.Windows.Forms.Button]::new()
    $configButton.Text = 'Protected folders...'
    $configButton.Width = 176
    Set-DeskPurgeBatchButtonStyle -Button $configButton -Variant 'Quiet'
    $buttonPanel.Controls.Add($configButton)

    $restartButton = $null
    $hasAdminRows = @($Plans | Where-Object { $_.Status -eq 'Needs admin' }).Count -gt 0
    if (-not (Test-DeskPurgeCurrentProcessElevated)) {
        $restartButton = [System.Windows.Forms.Button]::new()
        $restartButton.Text = 'Restart as admin'
        $restartButton.Width = 156
        $restartButton.Visible = $hasAdminRows
        Set-DeskPurgeBatchButtonStyle -Button $restartButton -Variant 'Quiet'
        $buttonPanel.Controls.Add($restartButton)
    }

    function Get-DeskPurgeCurrentFolderPlan {
        if ($null -eq $grid.CurrentRow) {
            return $null
        }

        $currentPlan = $grid.CurrentRow.Tag
        if ($null -ne $currentPlan -and
            -not [string]::IsNullOrWhiteSpace($currentPlan.FolderToDelete)) {
            return $currentPlan
        }

        return $null
    }

    function Get-DeskPurgeCurrentLargeFolderPlan {
        $currentPlan = Get-DeskPurgeCurrentFolderPlan
        if ($null -ne $currentPlan -and
            $currentPlan.Status -eq 'Ready' -and
            $currentPlan.LargeFolderWarning) {
            return $currentPlan
        }

        return $null
    }

    function Update-DeskPurgeBatchSelectionSummary {
        $selectedCount = 0
        $readyCount = 0
        $resolvingCount = 0
        $largeSelectedCount = 0
        $hasAdminRows = $false
        foreach ($row in $grid.Rows) {
            if ($row.Tag.Status -eq 'Ready') {
                $readyCount++
                if ([bool]$row.Cells['Selected'].Value) {
                    $selectedCount++
                    if ($row.Tag.LargeFolderWarning) {
                        $largeSelectedCount++
                    }
                }
            }
            elseif ($row.Tag.Status -eq 'Resolving') {
                $resolvingCount++
            }

            if ($row.Tag.Status -eq 'Needs admin') {
                $hasAdminRows = $true
            }
        }

        $summaryLabel.Text = "$selectedCount ready shortcut(s) selected, $readyCount ready"
        if ($resolvingCount -gt 0) {
            $summaryLabel.Text += ", $resolvingCount resolving"
        }
        $summaryLabel.Text += ", $($grid.Rows.Count) total"
        if ($selectedCount -ge 2) {
            [long]$totalSelectedBytes = 0
            $allHaveSize = $true
            foreach ($row in $grid.Rows) {
                if ($row.Tag.Status -eq 'Ready' -and [bool]$row.Cells['Selected'].Value) {
                    if ($null -ne $row.Tag.FolderSizeBytes) {
                        $totalSelectedBytes += [long]$row.Tag.FolderSizeBytes
                    }
                    else {
                        $allHaveSize = $false
                    }
                }
            }
            if ($allHaveSize -and $totalSelectedBytes -gt 0) {
                $summaryLabel.Text += " (total size: $(Format-FileSize -Bytes $totalSelectedBytes))"
            }
        }
        if ($largeSelectedCount -gt 0) {
            $summaryLabel.Text += ", $largeSelectedCount over 100 GB"
        }
        if ($streamPlans) {
            $messageLabel.Text = if ($resolvingCount -gt 0) {
                'DeskPurge is resolving these shortcuts into install folders. Only checked Ready rows will be permanently deleted.'
            }
            else {
                'DeskPurge resolved these shortcuts into install folders. Only checked Ready rows will be permanently deleted.'
            }
        }

        $currentFolderPlan = Get-DeskPurgeCurrentFolderPlan
        if ($null -ne $currentFolderPlan -and $currentFolderPlan.LargeFolderWarning) {
            $warningLabel.Text = "Large folder warning: $($currentFolderPlan.FolderSizeDisplay). Review Folder to delete and Boundary before deleting, or use Protect this folder."
            $warningPanel.Visible = $true
        }
        else {
            $warningLabel.Text = ''
            $warningPanel.Visible = $false
        }

        $deleteButton.Enabled = $selectedCount -gt 0
        $openButton.Enabled = $null -ne $currentFolderPlan
        $protectButton.Enabled = $null -ne (Get-DeskPurgeCurrentLargeFolderPlan)
        if ($null -ne $restartButton) {
            $restartButton.Visible = $hasAdminRows
        }
    }

    $grid.Add_CurrentCellDirtyStateChanged({
        if ($grid.IsCurrentCellDirty) {
            $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) | Out-Null
        }
    })
    $grid.Add_CellValueChanged({ Update-DeskPurgeBatchSelectionSummary })
    $grid.Add_SelectionChanged({ Update-DeskPurgeBatchSelectionSummary })

    $grid.Add_ColumnHeaderMouseClick({
        param($sender, $eventArgs)
        $clickedColumn = $grid.Columns[$eventArgs.ColumnIndex]
        if ($clickedColumn.Name -ne 'Size') {
            return
        }

        if ($script:DeskPurgeSizeSortDirection -eq 'Ascending') {
            $script:DeskPurgeSizeSortDirection = 'Descending'
        }
        else {
            $script:DeskPurgeSizeSortDirection = 'Ascending'
        }

        $sortedRows = @($grid.Rows | Sort-Object {
            $sizeBytes = $_.Tag.FolderSizeBytes
            if ($null -eq $sizeBytes) { [long]-1 } else { [long]$sizeBytes }
        })

        if ($script:DeskPurgeSizeSortDirection -eq 'Descending') {
            [array]::Reverse($sortedRows)
        }

        $preservedPlans = @($sortedRows | ForEach-Object { $_.Tag })
        $preservedChecks = @($sortedRows | ForEach-Object { [bool]$_.Cells['Selected'].Value })

        $grid.Rows.Clear()
        $rowsByShortcutPath.Clear()

        for ($i = 0; $i -lt $preservedPlans.Count; $i++) {
            $plan = $preservedPlans[$i]
            $rowIndex = $grid.Rows.Add(
                $preservedChecks[$i],
                (Get-DeskPurgeStatusDisplay -Plan $plan),
                $plan.FolderSizeDisplay,
                $plan.ShortcutName,
                $plan.FolderToDelete,
                $plan.TargetPath,
                $plan.ProtectedBoundary
            )
            $row = $grid.Rows[$rowIndex]
            $row.Tag = $plan
            Set-DeskPurgeBatchRowStatusStyle -Row $row

            $shortcutKey = ConvertTo-DeskPurgeNormalizedPath -Path $plan.ShortcutPath
            if ($shortcutKey) {
                $rowsByShortcutPath[$shortcutKey] = $row
            }
        }

        $sortGlyph = if ($script:DeskPurgeSizeSortDirection -eq 'Ascending') {
            [System.Windows.Forms.SortOrder]::Ascending
        }
        else {
            [System.Windows.Forms.SortOrder]::Descending
        }
        $clickedColumn.HeaderCell.SortGlyphDirection = $sortGlyph
        Update-DeskPurgeBatchSelectionSummary
    })

    $resolutionState = [pscustomobject]@{
        Job = $null
        Timer = $null
        StartTimer = $null
        RestoreAutoMinimizeTimer = $null
        Finished = $false
    }
    $receivedPlanKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Set-DeskPurgeBatchUnresolvedRowsError {
        param([Parameter(Mandatory = $true)][string]$Message)

        foreach ($row in $grid.Rows) {
            if ($row.Tag.Status -eq 'Resolving') {
                $errorPlan = New-DeskPurgeBatchErrorPlan `
                    -ShortcutPath $row.Tag.ShortcutPath `
                    -Status 'Error' `
                    -Message $Message
                Set-DeskPurgeBatchReviewRowPlan -Row $row -Plan $errorPlan
            }
        }
    }

    function Stop-DeskPurgeBatchResolutionState {
        if ($null -ne $resolutionState.Timer) {
            $resolutionState.Timer.Stop()
            $resolutionState.Timer.Dispose()
            $resolutionState.Timer = $null
        }

        if ($null -ne $resolutionState.StartTimer) {
            $resolutionState.StartTimer.Stop()
            $resolutionState.StartTimer.Dispose()
            $resolutionState.StartTimer = $null
        }

        if ($null -ne $resolutionState.RestoreAutoMinimizeTimer) {
            $resolutionState.RestoreAutoMinimizeTimer.Stop()
            $resolutionState.RestoreAutoMinimizeTimer.Dispose()
            $resolutionState.RestoreAutoMinimizeTimer = $null
        }

        if ($null -ne $resolutionState.Job) {
            if ($resolutionState.Job.State -notin @('Completed', 'Failed', 'Stopped')) {
                Stop-Job -Job $resolutionState.Job -ErrorAction SilentlyContinue | Out-Null
            }
            Remove-Job -Job $resolutionState.Job -Force -ErrorAction SilentlyContinue | Out-Null
            $resolutionState.Job = $null
        }

        $resolutionState.Finished = $true
    }

    function Receive-DeskPurgeBatchResolvedPlans {
        if ($null -eq $resolutionState.Job -or $resolutionState.Finished) {
            return
        }

        try {
            $receivedPlans = @(Receive-Job -Job $resolutionState.Job -Keep -ErrorAction SilentlyContinue)
        }
        catch {
            Set-DeskPurgeBatchUnresolvedRowsError -Message "Could not read background resolution results: $($_.Exception.Message)"
            Stop-DeskPurgeBatchResolutionState
            Update-DeskPurgeBatchSelectionSummary
            return
        }

        foreach ($plan in $receivedPlans) {
            if ($null -eq $plan -or [string]::IsNullOrWhiteSpace($plan.ShortcutPath)) {
                continue
            }

            $shortcutKey = ConvertTo-DeskPurgeNormalizedPath -Path $plan.ShortcutPath
            if (-not $shortcutKey -or -not $receivedPlanKeys.Add($shortcutKey)) {
                continue
            }

            if ($rowsByShortcutPath.ContainsKey($shortcutKey)) {
                Set-DeskPurgeBatchReviewRowPlan -Row $rowsByShortcutPath[$shortcutKey] -Plan $plan
            }
        }

        if ($resolutionState.Job.State -in @('Completed', 'Failed', 'Stopped')) {
            if ($resolutionState.Job.State -eq 'Failed') {
                $failureMessage = 'Background resolution failed before every shortcut could be reviewed.'
                if ($null -ne $resolutionState.Job.ChildJobs -and
                    $resolutionState.Job.ChildJobs.Count -gt 0 -and
                    $null -ne $resolutionState.Job.ChildJobs[0].JobStateInfo.Reason) {
                    $failureMessage = $resolutionState.Job.ChildJobs[0].JobStateInfo.Reason.Message
                }
                Set-DeskPurgeBatchUnresolvedRowsError -Message $failureMessage
            }
            else {
                Set-DeskPurgeBatchUnresolvedRowsError -Message 'Background resolution finished without returning a result for this shortcut.'
            }

            Stop-DeskPurgeBatchResolutionState
        }

        Update-DeskPurgeBatchSelectionSummary
    }

    $cancelButton.Add_Click({
        $form.Tag = [pscustomobject]@{ Action = 'Cancel'; Selected = @() }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Close()
    })

    $deletingPanel = [System.Windows.Forms.Panel]::new()
    $deletingPanel.Location = [System.Drawing.Point]::new($contentX, 76)
    $deletingPanel.Size = [System.Drawing.Size]::new($contentWidth, 624)
    $deletingPanel.BackColor = $palette.Surface
    $deletingPanel.Visible = $false
    $rootPanel.Controls.Add($deletingPanel)
    $deletingPanel.BringToFront()

    $deletingTitle = [System.Windows.Forms.Label]::new()
    $deletingTitle.Location = [System.Drawing.Point]::new(0, 200)
    $deletingTitle.Size = [System.Drawing.Size]::new($contentWidth, 40)
    $deletingTitle.Text = 'Deleting files...'
    $deletingTitle.Font = [System.Drawing.Font]::new('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
    $deletingTitle.ForeColor = $palette.Text
    $deletingTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $deletingPanel.Controls.Add($deletingTitle)

    $deletingMessage = [System.Windows.Forms.Label]::new()
    $deletingMessage.Location = [System.Drawing.Point]::new(0, 250)
    $deletingMessage.Size = [System.Drawing.Size]::new($contentWidth, 60)
    $deletingMessage.Text = "Please do not panic if the app temporarily becomes unresponsive."
    $deletingMessage.Font = [System.Drawing.Font]::new('Segoe UI', 10)
    $deletingMessage.ForeColor = $palette.Warning
    $deletingMessage.TextAlign = [System.Drawing.ContentAlignment]::TopCenter
    $deletingPanel.Controls.Add($deletingMessage)

    $deleteButton.Add_Click({
        $selectedPlans = [System.Collections.Generic.List[object]]::new()
        foreach ($row in $grid.Rows) {
            if ($row.Tag.Status -eq 'Ready' -and [bool]$row.Cells['Selected'].Value) {
                $selectedPlans.Add($row.Tag)
            }
        }
        
        $selectedArray = [object[]]$selectedPlans.ToArray()
        if ($selectedArray.Count -eq 0) { return }

        $headingLabel.Visible = $false
        $messageLabel.Visible = $false
        $grid.Visible = $false
        $warningPanel.Visible = $false
        $summaryLabel.Visible = $false
        $divider.Visible = $false
        $buttonPanel.Visible = $false
        $deletingPanel.Visible = $true
        $form.Refresh()

        $deleteResults = Invoke-DeskPurgeBatchDeletion -Plans $selectedArray
        $logFile = Write-DeskPurgeBatchLog -Results $deleteResults

        $deletingPanel.Visible = $false

        $deletedCount = @($deleteResults | Where-Object { $_.Status -eq 'Deleted' }).Count
        $warningCount = @($deleteResults | Where-Object { $_.Status -eq 'Shortcut failed' }).Count
        $failedCount = @($deleteResults | Where-Object { $_.Status -eq 'Failed' }).Count
        $isSingleResult = $deleteResults.Count -eq 1

        $doneBadgeLabel = [System.Windows.Forms.Label]::new()
        $doneBadgeLabel.Location = [System.Drawing.Point]::new($contentX, 66)
        $doneBadgeLabel.Size = [System.Drawing.Size]::new(96, 26)
        $doneBadgeLabel.Text = 'DONE'
        $doneBadgeLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $doneBadgeLabel.Font = [System.Drawing.Font]::new('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
        $doneBadgeLabel.BackColor = [System.Drawing.Color]::FromArgb(5, 46, 22)
        $doneBadgeLabel.ForeColor = $palette.Success
        $rootPanel.Controls.Add($doneBadgeLabel)
        $doneBadgeLabel.BringToFront()

        $headingLabel.Location = [System.Drawing.Point]::new($contentX, 100)
        $headingLabel.Text = 'Uninstall complete'
        $headingLabel.Visible = $true

        $totalFreedText = ''
        if ($deleteResults.Count -ge 2) {
            [long]$totalFreedBytes = 0
            $allHaveSize = $true
            foreach ($result in $deleteResults) {
                if ($result.Status -eq 'Deleted' -or $result.Status -eq 'Shortcut failed') {
                    $plan = $selectedArray | Where-Object { $_.ShortcutPath -eq $result.ShortcutPath } | Select-Object -First 1
                    if ($null -ne $plan -and $null -ne $plan.FolderSizeBytes) {
                        $totalFreedBytes += [long]$plan.FolderSizeBytes
                    }
                    else {
                        $allHaveSize = $false
                    }
                }
            }
            if ($allHaveSize -and $totalFreedBytes -gt 0) {
                $totalFreedText = " Total freed: $(Format-FileSize -Bytes $totalFreedBytes)."
            }
        }

        $messageLabel.Location = [System.Drawing.Point]::new($contentX, 140)
        $messageLabel.Text = if ($isSingleResult) {
            "$($deleteResults[0].Status): $($deleteResults[0].Message) Log: $logFile"
        }
        else {
            "$deletedCount deleted, $warningCount shortcut warning(s), $failedCount failed.$totalFreedText Log: $logFile"
        }
        $messageLabel.Visible = $true

        $compGrid = [System.Windows.Forms.DataGridView]::new()
        $compGrid.Location = [System.Drawing.Point]::new($contentX, 196)
        $compGrid.Size = [System.Drawing.Size]::new($contentWidth, 420)
        $compGrid.ReadOnly = $true
        Set-DeskPurgeBatchGridStyle -Grid $compGrid
        $rootPanel.Controls.Add($compGrid)

        foreach ($column in @(
            @{ Name = 'Status'; Text = 'Status'; Width = 120 },
            @{ Name = 'Shortcut'; Text = 'Shortcut'; Width = 200 },
            @{ Name = 'Freed'; Text = 'Freed'; Width = 90 },
            @{ Name = 'Message'; Text = 'Message'; Width = 360 },
            @{ Name = 'Folder'; Text = 'Folder'; Width = 260 }
        )) {
            $textColumn = [System.Windows.Forms.DataGridViewTextBoxColumn]::new()
            $textColumn.Name = $column.Name
            $textColumn.HeaderText = $column.Text
            $textColumn.Width = $column.Width
            if ($column.Name -eq 'Freed') {
                $textColumn.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Programmatic
            }
            $textColumn.ReadOnly = $true
            $compGrid.Columns.Add($textColumn) | Out-Null
        }

        $script:DeskPurgeFreedSortDirection = 'None'

        $compGrid.Add_ColumnHeaderMouseClick({
            param($sender, $eventArgs)
            $clickedColumn = $compGrid.Columns[$eventArgs.ColumnIndex]
            if ($clickedColumn.Name -ne 'Freed') {
                return
            }

            if ($script:DeskPurgeFreedSortDirection -eq 'Ascending') {
                $script:DeskPurgeFreedSortDirection = 'Descending'
            }
            else {
                $script:DeskPurgeFreedSortDirection = 'Ascending'
            }

            $sortedRows = @($compGrid.Rows | Sort-Object {
                $sizeText = [string]$_.Cells['Freed'].Value
                $currentShortcutName = [string]$_.Cells['Shortcut'].Value
                $matchedPlan = $selectedArray | Where-Object { $_.ShortcutName -eq $currentShortcutName } | Select-Object -First 1
                if ($null -ne $matchedPlan -and $null -ne $matchedPlan.FolderSizeBytes) {
                    return [long]$matchedPlan.FolderSizeBytes
                }
                # Parse the display string as fallback
                if ($sizeText -match '^([\d.]+)\s+(B|KB|MB|GB|TB|PB|EB)$') {
                    $num = [double]$matches[1]
                    $unit = $matches[2]
                    $multiplier = switch ($unit) {
                        'B'  { 1 }
                        'KB' { 1024 }
                        'MB' { [math]::Pow(1024, 2) }
                        'GB' { [math]::Pow(1024, 3) }
                        'TB' { [math]::Pow(1024, 4) }
                        'PB' { [math]::Pow(1024, 5) }
                        'EB' { [math]::Pow(1024, 6) }
                        default { 1 }
                    }
                    return [long]($num * $multiplier)
                }
                return [long]-1
            })

            if ($script:DeskPurgeFreedSortDirection -eq 'Descending') {
                [array]::Reverse($sortedRows)
            }

            $preservedData = @($sortedRows | ForEach-Object {
                [pscustomobject]@{
                    Status = [string]$_.Cells['Status'].Value
                    Shortcut = [string]$_.Cells['Shortcut'].Value
                    Freed = [string]$_.Cells['Freed'].Value
                    Message = [string]$_.Cells['Message'].Value
                    Folder = [string]$_.Cells['Folder'].Value
                    StatusColor = $_.Cells['Status'].Style.ForeColor
                }
            })

            $compGrid.Rows.Clear()

            foreach ($data in $preservedData) {
                $newRowIndex = $compGrid.Rows.Add(
                    $data.Status,
                    $data.Shortcut,
                    $data.Freed,
                    $data.Message,
                    $data.Folder
                )
                $newRow = $compGrid.Rows[$newRowIndex]
                if ($data.StatusColor -ne [System.Drawing.Color]::Empty) {
                    $newRow.Cells['Status'].Style.ForeColor = $data.StatusColor
                }
            }

            $sortGlyph = if ($script:DeskPurgeFreedSortDirection -eq 'Ascending') {
                [System.Windows.Forms.SortOrder]::Ascending
            }
            else {
                [System.Windows.Forms.SortOrder]::Descending
            }
            $clickedColumn.HeaderCell.SortGlyphDirection = $sortGlyph
        })

        foreach ($result in $deleteResults) {
            $rowIndex = $compGrid.Rows.Add(
                $result.Status,
                $result.ShortcutName,
                $result.FolderSizeDisplay,
                $result.Message,
                $result.FolderToDelete
            )
            $row = $compGrid.Rows[$rowIndex]
            switch ($result.Status) {
                'Deleted' { $row.Cells['Status'].Style.ForeColor = $palette.Success }
                'Shortcut failed' { $row.Cells['Status'].Style.ForeColor = $palette.Warning }
                default { $row.Cells['Status'].Style.ForeColor = $palette.Danger }
            }
        }

        $divider.Location = [System.Drawing.Point]::new($contentX, 638)
        $divider.Visible = $true

        $buttonPanel.Controls.Clear()
        $doneButton = [System.Windows.Forms.Button]::new()
        $doneButton.Text = 'Done'
        Set-DeskPurgeBatchButtonStyle -Button $doneButton -Variant 'Primary'
        $doneButton.Add_Click({
            $form.Tag = [pscustomobject]@{ Action = 'Done'; Selected = @() }
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        })
        $buttonPanel.Controls.Add($doneButton)
        $form.AcceptButton = $doneButton
        $form.CancelButton = $doneButton

        if ($isSingleResult -and -not [string]::IsNullOrWhiteSpace($deleteResults[0].FolderToDelete)) {
            $containingFolder = Split-Path -Path $deleteResults[0].FolderToDelete -Parent
            if (Test-Path -LiteralPath $containingFolder -PathType Container) {
                $openContainingButton = [System.Windows.Forms.Button]::new()
                $openContainingButton.Text = 'Open Containing Folder'
                $openContainingButton.Width = 184
                Set-DeskPurgeBatchButtonStyle -Button $openContainingButton -Variant 'Quiet'
                $openContainingButton.Add_Click({
                    try {
                        $form.TopMost = $false
                        Open-DeskPurgeBatchFolder -Path $containingFolder
                    }
                    catch {
                        [System.Windows.Forms.MessageBox]::Show("Could not open the folder.`n`n$($_.Exception.Message)", "Open Folder Failed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                    }
                })
                $buttonPanel.Controls.Add($openContainingButton)
            }
        }
        
        $buttonPanel.Visible = $true
    })

    if ($null -ne $restartButton) {
        $restartButton.Add_Click({
            $form.Tag = [pscustomobject]@{ Action = 'Elevate'; Selected = @() }
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        })
    }

    $openButton.Add_Click({
        $planToOpen = Get-DeskPurgeCurrentFolderPlan
        if ($null -eq $planToOpen) {
            return
        }

        try {
            $form.TopMost = $false
            Open-DeskPurgeBatchFolder -Path $planToOpen.FolderToDelete
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

    $configButton.Add_Click({
        Set-DeskPurgeBatchAutoMinimizeSuppressed -Form $form -Suppressed $true
        $wasTopMost = $form.TopMost
        try {
            $form.TopMost = $false
            $managerResult = Show-DeskPurgeProtectedFoldersManager -ConfigFile $ProtectedFoldersConfigFile -Owner $form
        }
        finally {
            Set-DeskPurgeBatchAutoMinimizeSuppressed -Form $form -Suppressed $false
            if (-not $form.IsDisposed) {
                $form.TopMost = $wasTopMost
                $form.Activate()
            }
        }

        if ($null -ne $managerResult -and $managerResult.Changed) {
            $form.Tag = [pscustomobject]@{
                Action = 'Refresh'
                Selected = @()
            }
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        }
    })

    $protectButton.Add_Click({
        $planToProtect = Get-DeskPurgeCurrentLargeFolderPlan
        if ($null -eq $planToProtect) {
            return
        }

        $form.Tag = [pscustomobject]@{
            Action = 'ProtectFolder'
            Selected = @()
            FolderToProtect = $planToProtect.FolderToDelete
        }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    function Start-DeskPurgeBatchReviewResolution {
        if (-not $streamPlans -or $resolutionState.Finished -or $null -ne $resolutionState.Job) {
            return
        }

        Set-DeskPurgeBatchAutoMinimizeSuppressed -Form $form -Suppressed $true
        try {
            if ($null -eq $ResolutionContext) {
                Set-DeskPurgeBatchUnresolvedRowsError -Message 'Could not start background resolution because protected folder context was not loaded.'
                Update-DeskPurgeBatchSelectionSummary
                return
            }

            $resolutionState.Job = Start-DeskPurgeBatchPlanResolutionJob `
                -Paths $Paths `
                -ResolutionContext $ResolutionContext
            $resolutionState.Timer = [System.Windows.Forms.Timer]::new()
            $resolutionState.Timer.Interval = 250
            $resolutionState.Timer.Add_Tick({ Receive-DeskPurgeBatchResolvedPlans })
            $resolutionState.Timer.Start()
        }
        catch {
            Set-DeskPurgeBatchUnresolvedRowsError -Message "Could not start background resolution: $($_.Exception.Message)"
            Update-DeskPurgeBatchSelectionSummary
        }
        finally {
            if (-not $form.IsDisposed) {
                $form.Activate()
            }

            if ($null -ne $resolutionState.RestoreAutoMinimizeTimer) {
                $resolutionState.RestoreAutoMinimizeTimer.Stop()
                $resolutionState.RestoreAutoMinimizeTimer.Dispose()
            }

            $resolutionState.RestoreAutoMinimizeTimer = [System.Windows.Forms.Timer]::new()
            $resolutionState.RestoreAutoMinimizeTimer.Interval = 700
            $resolutionState.RestoreAutoMinimizeTimer.Add_Tick({
                $resolutionState.RestoreAutoMinimizeTimer.Stop()
                $resolutionState.RestoreAutoMinimizeTimer.Dispose()
                $resolutionState.RestoreAutoMinimizeTimer = $null
                if (-not $form.IsDisposed) {
                    Set-DeskPurgeBatchAutoMinimizeSuppressed -Form $form -Suppressed $false
                }
            })
            $resolutionState.RestoreAutoMinimizeTimer.Start()
        }
    }

    $form.Add_Shown({
        if (-not $streamPlans) {
            return
        }

        $resolutionState.StartTimer = [System.Windows.Forms.Timer]::new()
        $resolutionState.StartTimer.Interval = 150
        $resolutionState.StartTimer.Add_Tick({
            $resolutionState.StartTimer.Stop()
            $resolutionState.StartTimer.Dispose()
            $resolutionState.StartTimer = $null
            Start-DeskPurgeBatchReviewResolution
        })
        $resolutionState.StartTimer.Start()
    })

    $form.Tag = [pscustomobject]@{ Action = 'Cancel'; Selected = @() }
    Update-DeskPurgeBatchSelectionSummary

    try {
        $form.ShowDialog() | Out-Null
        return $form.Tag
    }
    finally {
        Stop-DeskPurgeBatchResolutionState
        $form.Dispose()
    }
}

function ConvertTo-DeskPurgePowerShellSingleQuotedLiteral {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return "''"
    }

    return "'" + $Value.Replace("'", "''") + "'"
}

function Start-DeskPurgeBatchElevated {
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    $scriptLiteral = ConvertTo-DeskPurgePowerShellSingleQuotedLiteral -Value $PSCommandPath
    $pathLiterals = @($Paths | ForEach-Object { ConvertTo-DeskPurgePowerShellSingleQuotedLiteral -Value $_ })
    $command = "& $scriptLiteral -NoQueue $($pathLiterals -join ' ')"
    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))

    Start-Process `
        -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand) `
        -Verb RunAs `
        -ErrorAction Stop
}

function Invoke-DeskPurgeBatchDeletion {
    param([Parameter(Mandatory = $true)][object[]]$Plans)

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($plan in $Plans) {
        $result = [ordered]@{
            ShortcutName = $plan.ShortcutName
            ShortcutPath = $plan.ShortcutPath
            FolderToDelete = $plan.FolderToDelete
            FolderSizeDisplay = $plan.FolderSizeDisplay
            Status = 'Pending'
            Message = ''
        }

        try {
            if (Test-DeskPurgeTargetProcessRunning -TargetPath $plan.TargetPath) {
                throw "Target app is running."
            }

            if (-not [string]::IsNullOrWhiteSpace($plan.FolderToDelete)) {
                if (-not (Test-Path -LiteralPath $plan.FolderToDelete -PathType Container)) {
                    throw "Folder no longer exists."
                }

                Remove-Item -LiteralPath $plan.FolderToDelete -Recurse -Force -ErrorAction Stop
            }

            try {
                Remove-Item -LiteralPath $plan.ShortcutPath -Force -ErrorAction Stop
                $result.Status = 'Deleted'
                if (-not [string]::IsNullOrWhiteSpace($plan.FolderToDelete)) {
                    $result.Message = 'Folder and shortcut removed.'
                } else {
                    $result.Message = 'Shortcut removed.'
                }
            }
            catch {
                $result.Status = 'Shortcut failed'
                if (-not [string]::IsNullOrWhiteSpace($plan.FolderToDelete)) {
                    $result.Message = "Folder removed, but shortcut could not be removed: $($_.Exception.Message)"
                } else {
                    $result.Message = "Shortcut could not be removed: $($_.Exception.Message)"
                }
            }
        }
        catch {
            $result.Status = 'Failed'
            $result.Message = $_.Exception.Message
        }

        $results.Add([pscustomobject]$result)
    }

    return [object[]]$results.ToArray()
}

function Write-DeskPurgeBatchLog {
    param([Parameter(Mandatory = $true)][object[]]$Results)

    $logFile = Join-Path $PSScriptRoot "DeskPurge_Log.txt"
    $timestamp = Get-Date -Format 'yyyy-MM-dd hh:mm tt'
    $logEntries = [System.Collections.Generic.List[string]]::new()
    $logEntries.Add("DeskPurge uninstall:")

    foreach ($result in $Results) {
        $logEntries.Add("$($result.Status): $($result.ShortcutPath) -> $($result.FolderToDelete) ($($result.FolderSizeDisplay))")
        if (-not [string]::IsNullOrWhiteSpace($result.Message)) {
            $logEntries.Add("  $($result.Message)")
        }
    }

    $newBlock = @("[$timestamp]") + [string[]]$logEntries.ToArray() + @("---")

    if (Test-Path -LiteralPath $logFile -PathType Leaf) {
        $oldLines = Get-Content -LiteralPath $logFile -Encoding UTF8
        $newBlock | Out-File -FilePath $logFile -Encoding UTF8
        $oldLines | Out-File -FilePath $logFile -Encoding UTF8 -Append
    }
    else {
        $newBlock | Out-File -FilePath $logFile -Encoding UTF8
    }

    return $logFile
}



try {
    $ShortcutPaths = Get-DeskPurgeUniqueShortcutPaths -Paths $ShortcutPaths

    if (-not $NoQueue) {
        if ($ShortcutPaths.Count -eq 0) {
            Show-DeskPurgeBatchMessage `
                -Title 'Usage Error' `
                -Heading 'No shortcuts were provided' `
                -Message 'DeskPurge is intended for shortcut context-menu use.' `
                -Type 'Error'
            exit 1
        }

        $queueResult = Add-DeskPurgeBatchQueue -Paths $ShortcutPaths
        if (-not $queueResult.ShouldOpen) {
            exit 0
        }

        Start-Sleep -Milliseconds 1200
        $ShortcutPaths = Read-DeskPurgeBatchQueue -State $queueResult.State
    }

    $ShortcutPaths = Get-DeskPurgeUniqueShortcutPaths -Paths $ShortcutPaths
    if ($ShortcutPaths.Count -eq 0) {
        Show-DeskPurgeBatchMessage `
            -Title 'Usage Error' `
            -Heading 'No shortcuts were provided' `
            -Message 'DeskPurge did not receive any shortcut paths to review.' `
            -Type 'Error'
        exit 1
    }

    while ($true) {
        $resolutionContext = Get-DeskPurgeBatchResolutionContext -Paths $ShortcutPaths
        $reviewResult = Show-DeskPurgeBatchReview -Paths $ShortcutPaths -ResolutionContext $resolutionContext

        if ($reviewResult.Action -eq 'ProtectFolder') {
            Add-DeskPurgeProtectedFolderConfigEntry `
                -ConfigFile $ProtectedFoldersConfigFile `
                -FolderPath $reviewResult.FolderToProtect `
                -Comment 'Added by DeskPurge review after a large-folder warning on' | Out-Null
            continue
        }

        if ($reviewResult.Action -eq 'Refresh') {
            continue
        }

        if ($reviewResult.Action -eq 'Elevate') {
            Start-DeskPurgeBatchElevated -Paths $ShortcutPaths
            exit 0
        }

        exit 0
    }
}
catch {
    Show-DeskPurgeBatchMessage `
        -Title 'Unexpected Error' `
        -Heading 'Uninstall could not continue' `
        -Message "DeskPurge hit an unexpected script error before it could finish cleanly.`n`nTechnical detail:`n$($_.Exception.ToString())" `
        -Type 'Error'
    exit 1
}
