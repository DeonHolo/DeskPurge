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
