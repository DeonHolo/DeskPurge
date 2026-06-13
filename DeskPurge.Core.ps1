# Core helpers for DeskPurge. This file must stay free of GUI prompts and deletes
# so it can be loaded safely by tests.

function ConvertTo-DeskPurgeNormalizedPath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    return $Path.Trim().TrimEnd('\').TrimEnd('/').ToLowerInvariant()
}

function Test-DeskPurgeRootDrive {
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalized = ConvertTo-DeskPurgeNormalizedPath -Path $Path
    return $normalized -match '^[a-z]:\\?$'
}

function Add-DeskPurgeProtectedPath {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$ProtectedPaths,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $normalized = ConvertTo-DeskPurgeNormalizedPath -Path $Path
    if (-not $normalized) {
        return
    }

    [void]$ProtectedPaths.Add($normalized)

    if ($normalized -notmatch '\\steamapps\\common$') {
        $steamCommonPath = ConvertTo-DeskPurgeNormalizedPath -Path "$normalized\steamapps\common"
        [void]$ProtectedPaths.Add($steamCommonPath)
    }
}

function Get-ProtectedGameFolders {
    param([Parameter(Mandatory = $true)][string]$ConfigFile)

    if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
        throw "Protected folders config file not found: $ConfigFile"
    }

    $loadedProtectedFolders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    try {
        foreach ($rawLine in (Get-Content -LiteralPath $ConfigFile -ErrorAction Stop)) {
            $line = $rawLine.Trim()
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
                continue
            }

            Add-DeskPurgeProtectedPath -ProtectedPaths $loadedProtectedFolders -Path $line
        }
    }
    catch {
        throw "Error reading protected folders config file: $ConfigFile. $($_.Exception.Message)"
    }

    if ($loadedProtectedFolders.Count -eq 0) {
        throw "Protected folders config file has no active folder entries: $ConfigFile"
    }

    return [string[]]$loadedProtectedFolders
}

function Resolve-DeskPurgeDeletionTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InitialFolder,

        [string[]]$SystemProtectedPaths = @(),

        [string[]]$UserProtectedFolders = @(),

        [int]$MaxDepth = 10
    )

    if ([string]::IsNullOrWhiteSpace($InitialFolder)) {
        throw "Initial folder is empty."
    }

    $folderToDelete = $InitialFolder
    if (Test-DeskPurgeRootDrive -Path $folderToDelete) {
        throw "Refusing to select a root drive for deletion: $folderToDelete"
    }

    $protectedPathSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $SystemProtectedPaths + $UserProtectedFolders) {
        $normalizedPath = ConvertTo-DeskPurgeNormalizedPath -Path $path
        if ($normalizedPath) {
            [void]$protectedPathSet.Add($normalizedPath)
        }
    }

    for ($i = 0; $i -lt $MaxDepth; $i++) {
        $parentOfCurrentFolder = Split-Path -Path $folderToDelete -Parent
        if ([string]::IsNullOrWhiteSpace($parentOfCurrentFolder)) {
            break
        }

        $normalizedParent = ConvertTo-DeskPurgeNormalizedPath -Path $parentOfCurrentFolder
        if ((Test-DeskPurgeRootDrive -Path $normalizedParent) -or $protectedPathSet.Contains($normalizedParent)) {
            break
        }

        $folderToDelete = $parentOfCurrentFolder
        if (Test-DeskPurgeRootDrive -Path $folderToDelete) {
            throw "Refusing to select a root drive for deletion: $folderToDelete"
        }
    }

    return $folderToDelete
}

function Format-FileSize {
    param([long]$Bytes)

    $suffixes = "B", "KB", "MB", "GB", "TB", "PB", "EB"
    if ($Bytes -eq 0) {
        return "0 B"
    }

    $place = [Math]::Floor([Math]::Log($Bytes, 1024))
    if ($place -lt 0) {
        $place = 0
    }
    if ($place -ge $suffixes.Length) {
        $place = $suffixes.Length - 1
    }

    $num = $Bytes / [Math]::Pow(1024, $place)
    return "{0:N2} {1}" -f $num, $suffixes[$place]
}

function Get-DeskPurgeFolderSizeDisplay {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            return "N/A"
        }

        [long]$totalBytes = 0
        foreach ($item in (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue)) {
            $totalBytes += $item.Length
        }

        return Format-FileSize -Bytes $totalBytes
    }
    catch {
        return "Error calculating size"
    }
}
