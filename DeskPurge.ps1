# DeskPurge.ps1
param([string]$LinkPathFromContextMenu)

# --- Configuration: Define where to find the protected folders list ---
$ConfigFileName = "DeskPurge_ProtectedFolders.txt"
$ScriptPath = $PSScriptRoot
$ProtectedFoldersConfigFile = Join-Path -Path $ScriptPath -ChildPath $ConfigFileName

# --- GUI Helper Function ---
function Show-Popup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [ValidateSet('Info', 'Warning', 'Error', 'Question')]
        [string]$Type
    )
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    }
    catch {
        $criticalErrorLog = Join-Path $env:TEMP "DeskPurge_CriticalError.txt"
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
        "[$timestamp] FATAL SCRIPT ERROR:" | Out-File $criticalErrorLog -Append -Encoding UTF8
        "Could not load System.Windows.Forms for GUI pop-ups." | Out-File $criticalErrorLog -Append -Encoding UTF8
        "Script cannot continue as intended." | Out-File $criticalErrorLog -Append -Encoding UTF8
        "Attempted Action: $Title - $Message" | Out-File $criticalErrorLog -Append -Encoding UTF8
        "---" | Out-File $criticalErrorLog -Append -Encoding UTF8
        try { Start-Process notepad.exe $criticalErrorLog } catch {}
        exit 1
    }

    $ButtonType = [System.Windows.Forms.MessageBoxButtons]::OK
    $IconType = switch ($Type) {
        'Info'     { [System.Windows.Forms.MessageBoxIcon]::Information }
        'Warning'  { [System.Windows.Forms.MessageBoxIcon]::Warning }
        'Error'    { [System.Windows.Forms.MessageBoxIcon]::Error }
        'Question' {
            $ButtonType = [System.Windows.Forms.MessageBoxButtons]::YesNoCancel
            [System.Windows.Forms.MessageBoxIcon]::Question
        }
        default    { [System.Windows.Forms.MessageBoxIcon]::None }
    }
    
    $result = [System.Windows.Forms.MessageBox]::Show($Message, $Title, $ButtonType, $IconType)

    if ($Type -eq 'Error') { 
        exit 1 
    }
    return $result
}

# --- Function to load protected folders from config ---
function Get-ProtectedGameFolders {
    param([string]$ConfigFile)
    $loadedProtectedFolders = [System.Collections.Generic.List[string]]::new()
    if (Test-Path $ConfigFile) {
        try {
            Get-Content $ConfigFile | ForEach-Object {
                $line = $_.Trim()
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    $normalized = $line.TrimEnd('\').TrimEnd('/').ToLowerInvariant()
                    if ($normalized) {
                        $loadedProtectedFolders.Add($normalized)
                    }
                }
            }
        }
        catch {
            Show-Popup -Message "Error reading protected folders config file:`n$ConfigFile`n$($_.Exception.Message)" -Title "Config Error" -Type "Warning"
        }
    }
    return $loadedProtectedFolders
}

# --- Function to format bytes into readable string ---
function Format-FileSize {
    param([long]$bytes)
    $suf = "B", "KB", "MB", "GB", "TB", "PB", "EB"
    if ($bytes -eq 0) { return "0 B" }
    $place = [Math]::Floor([Math]::Log($bytes, 1024))
    if ($place -lt 0) {$place = 0}
    if ($place -ge $suf.Length) {$place = $suf.Length -1}
    $num = $bytes / [Math]::Pow(1024, $place)
    return "{0:N2} {1}" -f $num, $suf[$place]
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
        if ($shortcut -ne $null) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) | Out-Null }
        if ($shell -ne $null) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null }
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
    $userProtectedGameFolders = Get-ProtectedGameFolders -ConfigFile $ProtectedFoldersConfigFile

    # 3. Traverse upwards to find the true game installation folder to delete
    $folderToDelete = $initialFolderCandidate
    Write-Host "DEBUG: Initial folder candidate: $folderToDelete"
    for ($i = 0; $i -lt 10; $i++) {
        $parentOfCurrentFolder = Split-Path -Path $folderToDelete -Parent
        if ([string]::IsNullOrWhiteSpace($parentOfCurrentFolder)) { Write-Host "DEBUG: Reached root or invalid parent."; break }
        $normalizedParent = $parentOfCurrentFolder.TrimEnd('\').TrimEnd('/').ToLowerInvariant()
        Write-Host "DEBUG: Checking parent: $normalizedParent (of current $folderToDelete)"
        if (($normalizedParent -match '^[a-z]:\\?$') -or ($systemProtectedPaths -contains $normalizedParent) -or ($userProtectedGameFolders -contains $normalizedParent)) {
            Write-Host "DEBUG: Parent '$normalizedParent' is protected. '$folderToDelete' is the target."
            break
        }
        $folderToDelete = $parentOfCurrentFolder
        Write-Host "DEBUG: Moved up. New folderToDelete: $folderToDelete"
        if (($folderToDelete.TrimEnd('\').TrimEnd('/').ToLowerInvariant()) -match '^[a-z]:\\?$') { Write-Host "DEBUG: New folderToDelete '$folderToDelete' is a root drive."; break }
    }
    Write-Host "DEBUG: Final folder determined for deletion: $folderToDelete"

    # 4. Final Safety Checks on the *determined* $folderToDelete
    $normalizedFolderToDelete = $folderToDelete.TrimEnd('\').TrimEnd('/').ToLowerInvariant()
    if ($normalizedFolderToDelete -match '^[a-z]:\\?$') { Show-Popup -Message "SAFETY HALT! Final folder is root drive:`n$folderToDelete`nBlocked." -Title "DANGER - Root Drive" -Type "Error" }
    if ($systemProtectedPaths -contains $normalizedFolderToDelete) { Show-Popup -Message "SAFETY HALT! Final folder is system folder:`n$folderToDelete`nBlocked." -Title "DANGER - System Folder" -Type "Error" }
    if ($userProtectedGameFolders -contains $normalizedFolderToDelete) { Show-Popup -Message "SAFETY HALT! Final folder IS a main game library:`n$folderToDelete`nAborting." -Title "DANGER - Main Game Library" -Type "Error" }
    if (-not (Test-Path -LiteralPath $folderToDelete -PathType Container)) { Show-Popup -Message "Error: Final folder to delete is invalid:`n$folderToDelete" -Title "Invalid Final Folder" -Type "Error" }

    # --- Calculate Folder Size for Confirmation ---
    $folderSizeDisplay = "N/A"
    try {
        if (Test-Path -LiteralPath $folderToDelete -PathType Container) {
            $items = Get-ChildItem -LiteralPath $folderToDelete -Recurse -Force -ErrorAction SilentlyContinue
            if ($items) { $sizeInfo = $items | Measure-Object -Property Length -Sum; $folderSizeBytes = $sizeInfo.Sum; $folderSizeDisplay = Format-FileSize -bytes $folderSizeBytes } 
            else { $folderSizeDisplay = "0 B (or items inaccessible)" }
        }
    } catch { $folderSizeDisplay = "Error calculating size" }

    # 5. Confirmation
    $confirmationMessage = "Are you sure you want to permanently delete:`n`n1. Shortcut:`n$finalLinkPath`n`n2. AND ITS ENTIRE FOLDER (Size: $folderSizeDisplay):`n$folderToDelete`n`nThis cannot be undone."
    $userResponse = Show-Popup -Message $confirmationMessage -Title "CONFIRM UNINSTALL" -Type "Question"
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
                    Show-Popup -Message "The game/application '$targetExeName' appears to be running.`nPlease close it before attempting to uninstall.`n`nPath: $targetPath`n`nOperation aborted. Nothing was deleted." -Title "Application In Use" -Type "Error"
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
        $customMessage = "Could not delete the folder '$folderToDelete'.`nIt's likely that some files are currently in use by the game or another application.`n`nPlease ensure the game and any related programs are closed.`n`nError details: $errorMessage`n`n"
        Show-Popup -Message $customMessage -Title "Deletion Error - Files In Use" -Type "Error" 
        # This 'Error' type popup will cause the script to exit
    }
    catch { # Catch any other errors during folder deletion
        $errorMessage = $_.Exception.Message
        Write-Host "ERROR deleting folder (General Exception): $errorMessage"
        Show-Popup -Message "Failed to delete folder '$folderToDelete':`n$errorMessage`n`nOperation aborted. Shortcut was NOT deleted." -Title "Deletion Error (Folder)" -Type "Error"
        # This 'Error' type popup will cause the script to exit
    }

    # Only delete shortcut if folder deletion was successful
    if ($folderDeletedSuccessfully) {
        try {
            Write-Host "DEBUG: Attempting to delete shortcut: $finalLinkPath"
            Remove-Item -LiteralPath $finalLinkPath -Force
            $logEntries.Add("Deleted shortcut: $finalLinkPath")
            Write-Host "DEBUG: Shortcut deleted successfully."
        }
        catch {
            $errorMessage = "Failed to delete shortcut '$finalLinkPath' (folder was already deleted): $($_.Exception.Message)"
            $logEntries.Add("WARNING: $errorMessage") # Log as warning as main task (folder) succeeded
            Show-Popup -Message $errorMessage -Title "Deletion Warning (Shortcut)" -Type "Warning" 
            # This is a warning, script will continue to logging and completion message
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
        Show-Popup -Message "Uninstall process finished (or was halted due to an error).`nDetails logged to:`n$logFile" -Title "Operation Status" -Type "Info"
    } # Else, if user cancelled before any action, no log/completion message needed beyond exiting.

}
catch { # Catch-all for any other unhandled script errors
    Show-Popup -Message "An unexpected script error occurred:`n$($_.Exception.ToString())" -Title "TOP LEVEL SCRIPT ERROR" -Type "Error"
}