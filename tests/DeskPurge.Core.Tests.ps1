BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\DeskPurge.Core.ps1')
}

Describe 'ConvertTo-DeskPurgeNormalizedPath' {
    It 'trims trailing slashes and lowercases paths' {
        ConvertTo-DeskPurgeNormalizedPath -Path 'D:\Games\' | Should -Be 'd:\games'
    }
}

Describe 'Get-ProtectedGameFolders' {
    It 'throws when the config file is missing' {
        $missingPath = Join-Path -Path $TestDrive -ChildPath 'missing.txt'

        { Get-ProtectedGameFolders -ConfigFile $missingPath } | Should -Throw '*Protected folders config file not found*'
    }

    It 'throws when the config has no active folder entries' {
        $configPath = Join-Path -Path $TestDrive -ChildPath 'empty.txt'
        @(
            '# comment only'
            ''
            '   # another comment'
        ) | Set-Content -LiteralPath $configPath

        { Get-ProtectedGameFolders -ConfigFile $configPath } | Should -Throw '*no active folder entries*'
    }

    It 'ignores comments, normalizes paths, and expands Steam library roots' {
        $configPath = Join-Path -Path $TestDrive -ChildPath 'protected.txt'
        @(
            '# comments are ignored'
            'D:\Games\'
            'D:\SteamLibrary'
            'C:\Program Files (x86)\Steam\steamapps\common'
        ) | Set-Content -LiteralPath $configPath

        $folders = @(Get-ProtectedGameFolders -ConfigFile $configPath)

        $folders | Should -Contain 'd:\games'
        $folders | Should -Contain 'd:\games\steamapps\common'
        $folders | Should -Contain 'd:\steamlibrary'
        $folders | Should -Contain 'd:\steamlibrary\steamapps\common'
        $folders | Should -Contain 'c:\program files (x86)\steam\steamapps\common'
    }

    It 'loads protected folders from drives that are not currently mounted' {
        $configPath = Join-Path -Path $TestDrive -ChildPath 'offline-drive.txt'
        @(
            'Z:\OfflineLibrary'
        ) | Set-Content -LiteralPath $configPath

        $folders = @(Get-ProtectedGameFolders -ConfigFile $configPath)

        $folders | Should -Contain 'z:\offlinelibrary'
        $folders | Should -Contain 'z:\offlinelibrary\steamapps\common'
    }
}

Describe 'Get-DeskPurgeProtectedFolderCandidatesFromTargetPath' {
    It 'suggests a known game-library root from a selected shortcut target' {
        $candidates = @(Get-DeskPurgeProtectedFolderCandidatesFromTargetPath -TargetPath 'D:\Games\CoolGame\bin\game.exe')
        $paths = @($candidates | ForEach-Object { $_.Path })

        $paths | Should -Contain 'D:\Games'
    }

    It 'suggests steamapps common for Steam shortcut targets' {
        $candidates = @(Get-DeskPurgeProtectedFolderCandidatesFromTargetPath -TargetPath 'D:\SteamLibrary\steamapps\common\ExampleGame\game.exe')
        $paths = @($candidates | ForEach-Object { $_.Path })

        $paths | Should -Contain 'D:\SteamLibrary\steamapps\common'
    }

    It 'can suggest non-system top-level install folders' {
        $candidates = @(Get-DeskPurgeProtectedFolderCandidatesFromTargetPath -TargetPath 'D:\Program Files\ConvertTheSpireReborn\game.exe')
        $paths = @($candidates | ForEach-Object { $_.Path })

        $paths | Should -Contain 'D:\Program Files'
    }

    It 'does not suggest C Program Files as a first-run boundary' {
        $candidates = @(Get-DeskPurgeProtectedFolderCandidatesFromTargetPath -TargetPath 'C:\Program Files\ExampleGame\game.exe')
        $paths = @($candidates | ForEach-Object { $_.Path })

        $paths | Should -Not -Contain 'C:\Program Files'
    }
}

Describe 'Get-DeskPurgeUniqueShortcutPaths' {
    It 'normalizes and deduplicates shortcut paths without requiring the files to exist' {
        $paths = @(
            'C:\Users\Example\Desktop\Game.lnk'
            'C:\Users\Example\Desktop\Game.lnk\'
            '  C:\Users\Example\Desktop\Other.lnk  '
            ''
            $null
        )

        $uniquePaths = @(Get-DeskPurgeUniqueShortcutPaths -Paths $paths)

        $uniquePaths.Count | Should -Be 2
        $uniquePaths | Should -Contain 'C:\Users\Example\Desktop\Game.lnk'
        $uniquePaths | Should -Contain 'C:\Users\Example\Desktop\Other.lnk'
    }
}

Describe 'Test-DeskPurgeShortcutNeedsElevation' {
    It 'classifies public desktop shortcuts as admin-needed when the process is not elevated' {
        Test-DeskPurgeShortcutNeedsElevation `
            -ShortcutPath 'C:\Users\Public\Desktop\Game.lnk' `
            -IsElevated $false `
            -AdminShortcutRoots @('C:\Users\Public\Desktop') |
            Should -BeTrue
    }

    It 'does not require elevation for public desktop shortcuts when already elevated' {
        Test-DeskPurgeShortcutNeedsElevation `
            -ShortcutPath 'C:\Users\Public\Desktop\Game.lnk' `
            -IsElevated $true `
            -AdminShortcutRoots @('C:\Users\Public\Desktop') |
            Should -BeFalse
    }
}

Describe 'New-DeskPurgeShortcutPlan' {
    It 'rejects non-shortcut paths at row level' {
        $plan = New-DeskPurgeShortcutPlan `
            -ShortcutPath 'C:\Users\Example\Desktop\not-a-shortcut.txt' `
            -TargetPath 'C:\Games\Game\game.exe' `
            -SystemProtectedPaths @() `
            -UserProtectedFolders @() `
            -IsElevated $true

        $plan.Status | Should -Be 'Error'
        $plan.Message | Should -Be 'Not a shortcut (.lnk) file.'
    }

    It 'marks missing targets without selecting a deletion folder' {
        $plan = New-DeskPurgeShortcutPlan `
            -ShortcutPath 'C:\Users\Example\Desktop\Missing.lnk' `
            -TargetPath (Join-Path -Path $TestDrive -ChildPath 'missing.exe') `
            -SystemProtectedPaths @() `
            -UserProtectedFolders @() `
            -IsElevated $true

        $plan.Status | Should -Be 'Target missing'
        $plan.FolderToDelete | Should -BeNullOrEmpty
    }

    It 'blocks rows when final safety checks identify a protected folder target' {
        $libraryPath = Join-Path -Path $TestDrive -ChildPath 'Library'
        New-Item -Path $libraryPath -ItemType Directory | Out-Null
        $targetPath = Join-Path -Path $libraryPath -ChildPath 'game.exe'
        Set-Content -LiteralPath $targetPath -Value 'test'

        $plan = New-DeskPurgeShortcutPlan `
            -ShortcutPath 'C:\Users\Example\Desktop\Game.lnk' `
            -TargetPath $targetPath `
            -SystemProtectedPaths @() `
            -UserProtectedFolders @($TestDrive, $libraryPath) `
            -IsElevated $true

        $plan.Status | Should -Be 'Blocked'
        $plan.Message | Should -Match 'protected game-library folder'
    }

    It 'keeps large folder warnings soft while leaving the row ready' {
        $libraryPath = Join-Path -Path $TestDrive -ChildPath 'Library'
        $gamePath = Join-Path -Path $libraryPath -ChildPath 'HugeGame'
        New-Item -Path $gamePath -ItemType Directory | Out-Null
        $targetPath = Join-Path -Path $gamePath -ChildPath 'game.exe'
        Set-Content -LiteralPath $targetPath -Value '1234567890' -NoNewline

        $plan = New-DeskPurgeShortcutPlan `
            -ShortcutPath 'C:\Users\Example\Desktop\HugeGame.lnk' `
            -TargetPath $targetPath `
            -SystemProtectedPaths @() `
            -UserProtectedFolders @($libraryPath) `
            -IsElevated $true `
            -LargeFolderWarningThresholdBytes 1

        $plan.Status | Should -Be 'Ready'
        $plan.LargeFolderWarning | Should -BeTrue
        $plan.LargeFolderWarningMessage | Should -Match 'over 100 GB'
        $plan.FolderSizeBytes | Should -BeGreaterThan 1
    }
}

Describe 'Resolve-DeskPurgeDeletionTarget' {
    It 'returns the game folder for a nested target under a configured game library' {
        $target = Resolve-DeskPurgeDeletionTarget `
            -InitialFolder 'D:\Games\CoolGame\bin' `
            -SystemProtectedPaths @() `
            -UserProtectedFolders @('d:\games')

        $target | Should -Be 'D:\Games\CoolGame'
    }

    It 'keeps a direct game folder under a configured game library' {
        $target = Resolve-DeskPurgeDeletionTarget `
            -InitialFolder 'D:\Games\CoolGame' `
            -SystemProtectedPaths @() `
            -UserProtectedFolders @('d:\games')

        $target | Should -Be 'D:\Games\CoolGame'
    }

    It 'returns the game folder for Steam library roots expanded to steamapps common' {
        $target = Resolve-DeskPurgeDeletionTarget `
            -InitialFolder 'D:\SteamLibrary\steamapps\common\ExampleGame\bin' `
            -SystemProtectedPaths @() `
            -UserProtectedFolders @('d:\steamlibrary', 'd:\steamlibrary\steamapps\common')

        $target | Should -Be 'D:\SteamLibrary\steamapps\common\ExampleGame'
    }

    It 'returns the game folder for explicit steamapps common boundaries' {
        $target = Resolve-DeskPurgeDeletionTarget `
            -InitialFolder 'C:\Program Files (x86)\Steam\steamapps\common\ExampleGame\bin' `
            -SystemProtectedPaths @() `
            -UserProtectedFolders @('c:\program files (x86)\steam\steamapps\common')

        $target | Should -Be 'C:\Program Files (x86)\Steam\steamapps\common\ExampleGame'
    }

    It 'does not return a root drive as a deletion target' {
        { Resolve-DeskPurgeDeletionTarget -InitialFolder 'D:\' -SystemProtectedPaths @() -UserProtectedFolders @() } |
            Should -Throw '*root drive*'
    }
}

Describe 'Format-FileSize' {
    It 'formats zero bytes' {
        Format-FileSize -Bytes 0 | Should -Be '0 B'
    }

    It 'formats bytes as kilobytes' {
        Format-FileSize -Bytes 1536 | Should -Be '1.50 KB'
    }
}

Describe 'Get-DeskPurgeFolderSizeDisplay' {
    It 'returns zero for an empty folder' {
        $folderPath = Join-Path -Path $TestDrive -ChildPath 'empty-folder'
        New-Item -Path $folderPath -ItemType Directory | Out-Null

        Get-DeskPurgeFolderSizeDisplay -Path $folderPath | Should -Be '0 B'
    }

    It 'streams and sums file lengths' {
        $folderPath = Join-Path -Path $TestDrive -ChildPath 'size-folder'
        $childPath = Join-Path -Path $folderPath -ChildPath 'nested'
        New-Item -Path $childPath -ItemType Directory | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $folderPath -ChildPath 'one.bin') -Value '12345' -NoNewline
        Set-Content -LiteralPath (Join-Path -Path $childPath -ChildPath 'two.bin') -Value '1234567' -NoNewline

        Get-DeskPurgeFolderSizeDisplay -Path $folderPath | Should -Be '12 B'
    }
}
