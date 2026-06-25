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

function New-DeskPurgeProtectedFolderCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Source
    )

    return [pscustomobject]@{
        Path = $Path.Trim().TrimEnd('\').TrimEnd('/')
        Source = $Source
    }
}

function Add-DeskPurgeProtectedFolderCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.Dictionary[string, object]]$CandidatesByPath,

        [AllowNull()][string]$Path,

        [Parameter(Mandatory = $true)][string]$Source
    )

    $normalizedPath = ConvertTo-DeskPurgeNormalizedPath -Path $Path
    if (-not $normalizedPath) {
        return
    }

    if (Test-DeskPurgeRootDrive -Path $normalizedPath) {
        return
    }

    if (-not $CandidatesByPath.ContainsKey($normalizedPath)) {
        $CandidatesByPath[$normalizedPath] = New-DeskPurgeProtectedFolderCandidate -Path $Path -Source $Source
        return
    }

    $existing = $CandidatesByPath[$normalizedPath]
    if ($existing.Source -notlike "*$Source*") {
        $existing.Source = "$($existing.Source); $Source"
    }
}

function Join-DeskPurgePathSegments {
    param(
        [Parameter(Mandatory = $true)][string]$Drive,
        [Parameter(Mandatory = $true)][string[]]$Segments,
        [Parameter(Mandatory = $true)][int]$LastIndex
    )

    if ($LastIndex -lt 0 -or $Segments.Count -eq 0) {
        return $null
    }

    return "$Drive\" + (($Segments[0..$LastIndex]) -join '\')
}

function Get-DeskPurgeProtectedFolderCandidatesFromTargetPath {
    param([AllowNull()][string]$TargetPath)

    $candidatesByPath = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        return @()
    }

    $trimmedPath = $TargetPath.Trim().TrimEnd('\').TrimEnd('/')
    if ($trimmedPath -notmatch '^([a-zA-Z]:)\\(.+)$') {
        return @()
    }

    $drive = $matches[1]
    $segments = @($matches[2] -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($segments.Count -lt 2) {
        return @()
    }

    for ($index = 0; $index -lt ($segments.Count - 1); $index++) {
        if ($segments[$index].Equals('steamapps', [System.StringComparison]::OrdinalIgnoreCase) -and
            $segments[$index + 1].Equals('common', [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-DeskPurgeProtectedFolderCandidate `
                -CandidatesByPath $candidatesByPath `
                -Path (Join-DeskPurgePathSegments -Drive $drive -Segments $segments -LastIndex ($index + 1)) `
                -Source 'Steam library from selected shortcut'
        }
    }

    $knownSingleFolderLibraries = @(
        'Games',
        'Games2',
        '~Games~',
        'EpicGames',
        'Epic Games',
        'GOG Games',
        'Origin Games',
        'XboxGames',
        'WindowsApps'
    )

    for ($index = 0; $index -lt ($segments.Count - 1); $index++) {
        if ($knownSingleFolderLibraries -contains $segments[$index]) {
            Add-DeskPurgeProtectedFolderCandidate `
                -CandidatesByPath $candidatesByPath `
                -Path (Join-DeskPurgePathSegments -Drive $drive -Segments $segments -LastIndex $index) `
                -Source 'Known game-library folder from selected shortcut'
        }

        if ($segments[$index].Equals('Ubisoft Game Launcher', [System.StringComparison]::OrdinalIgnoreCase) -and
            $index + 1 -lt $segments.Count -and
            $segments[$index + 1].Equals('games', [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-DeskPurgeProtectedFolderCandidate `
                -CandidatesByPath $candidatesByPath `
                -Path (Join-DeskPurgePathSegments -Drive $drive -Segments $segments -LastIndex ($index + 1)) `
                -Source 'Ubisoft library from selected shortcut'
        }
    }

    $topLevelCandidate = Join-DeskPurgePathSegments -Drive $drive -Segments $segments -LastIndex 0
    $normalizedTopLevel = ConvertTo-DeskPurgeNormalizedPath -Path $topLevelCandidate
    $skipTopLevel = @(
        'c:\windows',
        'c:\users',
        'c:\program files',
        'c:\program files (x86)'
    )
    if ($skipTopLevel -notcontains $normalizedTopLevel) {
        Add-DeskPurgeProtectedFolderCandidate `
            -CandidatesByPath $candidatesByPath `
            -Path $topLevelCandidate `
            -Source 'Top-level folder from selected shortcut'
    }

    return @($candidatesByPath.Values)
}

function Get-DeskPurgeCommonProtectedFolderCandidatePaths {
    $candidatePaths = [System.Collections.Generic.List[string]]::new()
    $driveRoots = @()

    try {
        $driveRoots = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root.TrimEnd('\') })
    }
    catch {
        $driveRoots = @('C:', 'D:', 'E:')
    }

    foreach ($driveRoot in $driveRoots) {
        foreach ($relativePath in @(
            'Games',
            'Games2',
            '~Games~',
            'SteamLibrary\steamapps\common',
            'Steam\steamapps\common',
            'EpicGames',
            'Epic Games',
            'GOG Games',
            'Origin Games',
            'XboxGames'
        )) {
            $candidatePath = "$driveRoot\$relativePath"
            if (Test-Path -LiteralPath $candidatePath -PathType Container) {
                $candidatePaths.Add($candidatePath)
            }
        }
    }

    return [string[]]$candidatePaths
}

function Get-DeskPurgeSystemProtectedPaths {
    $paths = @(
        'c:\windows',
        'c:\program files',
        'c:\program files (x86)',
        [Environment]::GetFolderPath('UserProfile'),
        [Environment]::GetFolderPath('CommonDesktopDirectory'),
        [Environment]::GetFolderPath('Desktop')
    )

    return [string[]]($paths | ForEach-Object {
        ConvertTo-DeskPurgeNormalizedPath -Path $_
    } | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    })
}

function Get-DeskPurgeUniqueShortcutPaths {
    param([AllowNull()][string[]]$Paths)

    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $uniquePaths = [System.Collections.Generic.List[string]]::new()

    foreach ($path in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        $trimmedPath = $path.Trim()
        $normalizedPath = ConvertTo-DeskPurgeNormalizedPath -Path $trimmedPath
        if (-not $normalizedPath) {
            continue
        }

        if ($seenPaths.Add($normalizedPath)) {
            $uniquePaths.Add($trimmedPath)
        }
    }

    return [string[]]$uniquePaths
}

function Test-DeskPurgeCurrentProcessElevated {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-DeskPurgePathUnderFolder {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Folder
    )

    $normalizedPath = ConvertTo-DeskPurgeNormalizedPath -Path $Path
    $normalizedFolder = ConvertTo-DeskPurgeNormalizedPath -Path $Folder

    if (-not $normalizedPath -or -not $normalizedFolder) {
        return $false
    }

    return ($normalizedPath -eq $normalizedFolder) -or $normalizedPath.StartsWith("$normalizedFolder\")
}

function Test-DeskPurgeShortcutNeedsElevation {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [bool]$IsElevated = (Test-DeskPurgeCurrentProcessElevated),
        [string[]]$AdminShortcutRoots = @([Environment]::GetFolderPath('CommonDesktopDirectory'))
    )

    if ($IsElevated) {
        return $false
    }

    foreach ($root in @($AdminShortcutRoots)) {
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }

        if (Test-DeskPurgePathUnderFolder -Path $ShortcutPath -Folder $root) {
            return $true
        }
    }

    return $false
}

function Test-DeskPurgeTargetProcessRunning {
    param([AllowNull()][string]$TargetPath)

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        return $false
    }

    $targetExeName = Split-Path -Path $TargetPath -Leaf
    if ([string]::IsNullOrWhiteSpace($targetExeName)) {
        return $false
    }

    $processNameToFind = $targetExeName -replace '\.exe$', ''
    try {
        $runningProcesses = Get-Process -Name $processNameToFind -ErrorAction SilentlyContinue
        foreach ($process in @($runningProcesses)) {
            try {
                if ($process.Path -eq $TargetPath) {
                    return $true
                }
            }
            catch {
                continue
            }
        }
    }
    catch {
        return $false
    }

    return $false
}

function New-DeskPurgeShortcutPlan {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [AllowNull()][string]$TargetPath,
        [string[]]$SystemProtectedPaths = @(),
        [string[]]$UserProtectedFolders = @(),
        [bool]$IsElevated = (Test-DeskPurgeCurrentProcessElevated),
        [long]$LargeFolderWarningThresholdBytes = 100GB
    )

    $plan = [ordered]@{
        ShortcutPath = $ShortcutPath
        ShortcutName = Split-Path -Path $ShortcutPath -Leaf
        TargetPath = $TargetPath
        FolderToDelete = $null
        FolderSizeBytes = $null
        FolderSizeDisplay = 'N/A'
        ProtectedBoundary = $null
        LargeFolderWarning = $false
        LargeFolderWarningMessage = $null
        Status = 'Ready'
        Message = 'Ready'
    }

    if ([string]::IsNullOrWhiteSpace($ShortcutPath) -or -not $ShortcutPath.ToLowerInvariant().EndsWith('.lnk')) {
        $plan.Status = 'Error'
        $plan.Message = 'Not a shortcut (.lnk) file.'
        return [pscustomobject]$plan
    }

    if (Test-DeskPurgeShortcutNeedsElevation -ShortcutPath $ShortcutPath -IsElevated $IsElevated) {
        $plan.Status = 'Needs admin'
        $plan.Message = 'Shortcut is in a shared location that requires admin rights.'
    }

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        $plan.Status = 'Error'
        $plan.Message = 'Shortcut target is empty.'
        return [pscustomobject]$plan
    }

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        $plan.Status = 'Ready'
        $plan.Message = 'Shortcut target no longer exists. Only the shortcut will be deleted.'
        return [pscustomobject]$plan
    }

    $initialFolderCandidate = Split-Path -Path $TargetPath -Parent
    if ([string]::IsNullOrWhiteSpace($initialFolderCandidate) -or -not (Test-Path -LiteralPath $initialFolderCandidate -PathType Container)) {
        $plan.Status = 'Error'
        $plan.Message = 'Could not determine the target parent folder.'
        return [pscustomobject]$plan
    }

    try {
        $folderToDelete = Resolve-DeskPurgeDeletionTarget `
            -InitialFolder $initialFolderCandidate `
            -SystemProtectedPaths $SystemProtectedPaths `
            -UserProtectedFolders $UserProtectedFolders

        $normalizedFolderToDelete = ConvertTo-DeskPurgeNormalizedPath -Path $folderToDelete
        if (Test-DeskPurgeRootDrive -Path $normalizedFolderToDelete) {
            throw "Selected target is a root drive."
        }
        if ($SystemProtectedPaths -contains $normalizedFolderToDelete) {
            throw "Selected target is a protected system folder."
        }
        if ($UserProtectedFolders -contains $normalizedFolderToDelete) {
            throw "Selected target is a protected game-library folder."
        }
        if (-not (Test-Path -LiteralPath $folderToDelete -PathType Container)) {
            throw "Selected target folder could not be verified."
        }

        $plan.FolderToDelete = $folderToDelete
        $folderSizeBytes = Get-DeskPurgeFolderSizeBytes -Path $folderToDelete
        $plan.FolderSizeBytes = $folderSizeBytes
        $plan.FolderSizeDisplay = if ($null -ne $folderSizeBytes) {
            Format-FileSize -Bytes $folderSizeBytes
        }
        else {
            "Error calculating size"
        }
        $plan.ProtectedBoundary = Split-Path -Path $folderToDelete -Parent
        if ($null -ne $folderSizeBytes -and $folderSizeBytes -gt $LargeFolderWarningThresholdBytes) {
            $plan.LargeFolderWarning = $true
            $plan.LargeFolderWarningMessage = "This folder is over 100 GB. That can be normal for large games, but it can also mean DeskPurge found a parent/root folder. Review the folder and boundary before deleting."
        }

        if ($plan.Status -eq 'Ready' -and (Test-DeskPurgeTargetProcessRunning -TargetPath $TargetPath)) {
            $plan.Status = 'Running'
            $plan.Message = 'Target app appears to be running.'
        }
    }
    catch {
        $plan.Status = 'Blocked'
        $plan.Message = $_.Exception.Message
    }

    return [pscustomobject]$plan
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

function Get-DeskPurgeFolderSizeBytes {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            return $null
        }

        [long]$totalBytes = 0
        foreach ($item in (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue)) {
            $totalBytes += $item.Length
        }

        return $totalBytes
    }
    catch {
        return $null
    }
}

function Get-DeskPurgeFolderSizeDisplay {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return "N/A"
    }

    $totalBytes = Get-DeskPurgeFolderSizeBytes -Path $Path
    if ($null -eq $totalBytes) {
        return "Error calculating size"
    }

    return Format-FileSize -Bytes $totalBytes
}
