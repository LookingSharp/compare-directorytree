<#
.SYNOPSIS
    Validation tests for Compare-DirectoryTree.

.DESCRIPTION
    These tests validate the acceptance scenarios in Section 10 and the
    engineering and test invariants in Appendix B of
    ../../specs/Compare-DirectoryTree-Spec.md.
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..' 'Compare-DirectoryTree.ps1' | Resolve-Path | Select-Object -ExpandProperty Path
    . $script:ScriptPath

    function New-TestDirectoryPair {
        $base = Join-Path ([System.IO.Path]::GetTempPath()) ('cdt-' + [guid]::NewGuid().ToString('n'))
        $left = Join-Path $base 'left'
        $right = Join-Path $base 'right'
        New-Item -ItemType Directory -Path $left, $right -Force | Out-Null
        [pscustomobject]@{ Base = $base; Left = $left; Right = $right }
    }

    function New-TestFile {
        param(
            [Parameter(Mandatory)][string] $Path,
            [long] $Size = 0
        )

        $directory = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        $stream = [System.IO.File]::Create($Path)
        try { $stream.SetLength($Size) } finally { $stream.Dispose() }
    }

    function Get-SummaryValue {
        param(
            [Parameter(Mandatory)][AllowEmptyString()][string[]] $Report,
            [Parameter(Mandatory)][string] $Label
        )

        $line = $Report | Where-Object { $_ -like "$Label*" } | Select-Object -First 1
        if (-not $line) { throw "Summary label not found: $Label" }
        [long]($line.Substring($Label.Length).Trim())
    }

    function Get-DifferenceRow {
        param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]] $Report)

        $Report | Where-Object { $_ -match '^(<<|>>|<>)\s' }
    }

    function Get-VerdictLine {
        param([Parameter(Mandatory)][AllowEmptyString()][string[]] $Report)

        $Report | Where-Object { $_ -like 'RESULT:*' } | Select-Object -First 1
    }

    function Get-FileSystemSnapshot {
        param([Parameter(Mandatory)][string] $Path)

        Get-ChildItem -LiteralPath $Path -Recurse -Force |
            Sort-Object -Property FullName |
            ForEach-Object { '{0}|{1}|{2:o}' -f $_.FullName, $(if ($_.PSIsContainer) { 'dir' } else { $_.Length }), $_.LastWriteTimeUtc }
    }
}

Describe 'Compare-DirectoryTree' {
    BeforeEach {
        $script:Pair = New-TestDirectoryPair
        $script:Left = $script:Pair.Left
        $script:Right = $script:Pair.Right
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Pair.Base -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'Scenario 10.1 - same ordinary files' {
        It 'reports SAME with no differences' {
            New-TestFile (Join-Path $Left 'IMG_1001.JPG') 5000
            New-TestFile (Join-Path $Left 'IMG_1002.JPG') 6000
            New-TestFile (Join-Path $Right 'IMG_1001.JPG') 5000
            New-TestFile (Join-Path $Right 'IMG_1002.JPG') 6000

            $report = Compare-DirectoryTree $Left $Right -NoColor

            Get-SummaryValue $report 'Same:' | Should -Be 2
            Get-SummaryValue $report 'Total differences:' | Should -Be 0
            Get-SummaryValue $report 'Relevant differences:' | Should -Be 0
            Get-VerdictLine $report | Should -Be 'RESULT: SAME - all 2 files match'
            Get-DifferenceRow $report | Should -BeNullOrEmpty
        }
    }

    Context 'Scenario 10.2 - file only on LEFT' {
        It 'emits one LEFT-only row with a missing RIGHT size' {
            New-TestFile (Join-Path $Left 'IMG_1003.JPG') 4096

            $report = Compare-DirectoryTree $Left $Right -NoColor
            $rows = @(Get-DifferenceRow $report)

            $rows.Count | Should -Be 1
            $rows[0] | Should -Match '^<<\s+IMG_1003\.JPG\s+4,096\s+<missing>$'
            Get-SummaryValue $report 'LEFT only:' | Should -Be 1
            Get-SummaryValue $report 'Relevant differences:' | Should -Be 1
        }
    }

    Context 'Scenario 10.3 - file only on RIGHT' {
        It 'emits one RIGHT-only row with a missing LEFT size' {
            New-TestFile (Join-Path $Right 'IMG_1004.JPG') 2048

            $report = Compare-DirectoryTree $Left $Right -NoColor
            $rows = @(Get-DifferenceRow $report)

            $rows.Count | Should -Be 1
            $rows[0] | Should -Match '^>>\s+IMG_1004\.JPG\s+<missing>\s+2,048$'
            Get-SummaryValue $report 'RIGHT only:' | Should -Be 1
            Get-SummaryValue $report 'Relevant differences:' | Should -Be 1
        }
    }

    Context 'Scenario 10.4 - same filename, different size' {
        It 'emits exactly one different-size row and one relevant difference' {
            New-TestFile (Join-Path $Left 'IMG_1005.JPG') 5238104
            New-TestFile (Join-Path $Right 'IMG_1005.JPG') 5238105

            $report = Compare-DirectoryTree $Left $Right -NoColor
            $rows = @(Get-DifferenceRow $report)

            $rows.Count | Should -Be 1
            $rows[0] | Should -Match '^<>\s+IMG_1005\.JPG\s+5,238,104\s+5,238,105$'
            Get-SummaryValue $report 'Different size:' | Should -Be 1
            Get-SummaryValue $report 'Relevant differences:' | Should -Be 1
            Get-VerdictLine $report | Should -Be 'RESULT: NOT THE SAME - 1 relevant difference'
        }
    }

    Context 'Scenario 10.5 - ignored metadata only' {
        It 'keeps the row visible but does not make it relevant' {
            New-TestFile (Join-Path $Left 'IMG_1001.JPG') 5000
            New-TestFile (Join-Path $Right 'IMG_1001.JPG') 5000
            New-TestFile (Join-Path $Left 'Thumbs.db') 81920

            $report = Compare-DirectoryTree $Left $Right -NoColor
            $rows = @(Get-DifferenceRow $report)

            $rows.Count | Should -Be 1
            $rows[0] | Should -Match '^<<\s+Thumbs\.db\s+81,920\s+<missing>\s+Ignored: Windows thumbnail cache$'
            Get-SummaryValue $report 'Total differences:' | Should -Be 1
            Get-SummaryValue $report 'Ignored metadata differences:' | Should -Be 1
            Get-SummaryValue $report 'Relevant differences:' | Should -Be 0
            Get-VerdictLine $report | Should -Be 'RESULT: SAME - qualified: differences limited to 1 ignored metadata file'
        }

        It 'ignores every catalog entry listed in Appendix A.1' {
            foreach ($name in @('Thumbs.db', 'ehthumbs.db', 'desktop.ini', '.DS_Store', '.directory')) {
                Test-CDTIgnoredFile -FileName $name | Should -BeTrue -Because "$name is an Appendix A.1 rule"
            }
        }

        It 'recognizes Windows metadata names case-insensitively' {
            Test-CDTIgnoredFile -FileName 'THUMBS.DB' | Should -BeTrue
            Test-CDTIgnoredFile -FileName 'Desktop.INI' | Should -BeTrue
        }

        It 'does not ignore a file merely because it is hidden, dotted, or small' {
            New-TestFile (Join-Path $Left '.config') 1

            $report = Compare-DirectoryTree $Left $Right -NoColor

            Get-SummaryValue $report 'Ignored metadata differences:' | Should -Be 0
            Get-SummaryValue $report 'Relevant differences:' | Should -Be 1
        }
    }

    Context 'Scenario 10.6 - recognized metadata that remains relevant' {
        It 'treats an XMP sidecar as a relevant difference' {
            New-TestFile (Join-Path $Right 'IMG_1006.xmp') 512

            $report = Compare-DirectoryTree $Left $Right -NoColor
            $rows = @(Get-DifferenceRow $report)

            $rows[0] | Should -Match 'Recognized: XMP photo sidecar$'
            Get-SummaryValue $report 'Ignored metadata differences:' | Should -Be 0
            Get-SummaryValue $report 'Relevant differences:' | Should -Be 1
            Get-VerdictLine $report | Should -BeLike 'RESULT: NOT THE SAME*'
        }

        It 'recognizes every Appendix A.2 entry without ignoring it' {
            foreach ($name in @('._IMG_1001.JPG', 'IMG_1001.xmp', 'IMG_1001.aae', 'IMG_1001.pxd-sidecar', '.picasa.ini', 'Picasa.ini')) {
                $classification = Get-CDTMetadataClassification -FileName $name
                $classification | Should -Not -BeNullOrEmpty -Because "$name is an Appendix A.2 rule"
                $classification.Policy | Should -Be 'Relevant'
            }
        }

        It 'resolves overlapping catalog rules deterministically and preservation-first' {
            $first = Get-CDTMetadataClassification -FileName '._IMG_1001.xmp'
            $second = Get-CDTMetadataClassification -FileName '._IMG_1001.xmp'

            $first.Id | Should -Be $second.Id
            $first.Policy | Should -Be 'Relevant'
        }
    }

    Context 'Scenario 10.7 - hidden or system ordinary file' {
        It 'includes hidden and system files as relevant differences' {
            $hidden = Join-Path $Left 'hidden.dat'
            New-TestFile $hidden 10
            (Get-Item -LiteralPath $hidden -Force).Attributes = 'Hidden, System'

            $report = Compare-DirectoryTree $Left $Right -NoColor
            $rows = @(Get-DifferenceRow $report)

            $rows.Count | Should -Be 1
            $rows[0] | Should -Match '^<<\s+hidden\.dat\s'
            Get-SummaryValue $report 'LEFT files:' | Should -Be 1
            Get-SummaryValue $report 'Relevant differences:' | Should -Be 1
        }
    }

    Context 'Scenario 10.8 - both directories empty' {
        It 'reports SAME with zero counts' {
            $report = Compare-DirectoryTree $Left $Right -NoColor

            Get-SummaryValue $report 'LEFT files:' | Should -Be 0
            Get-SummaryValue $report 'RIGHT files:' | Should -Be 0
            Get-SummaryValue $report 'Total differences:' | Should -Be 0
            Get-SummaryValue $report 'Relevant differences:' | Should -Be 0
            Get-VerdictLine $report | Should -Be 'RESULT: SAME - all 0 files match'
        }
    }

    Context 'Scenario 10.9 - one directory empty' {
        It 'reports every file on the populated side and applies metadata policy' {
            New-TestFile (Join-Path $Left 'a.txt') 1
            New-TestFile (Join-Path $Left 'b.txt') 2
            New-TestFile (Join-Path $Left 'Thumbs.db') 3

            $report = Compare-DirectoryTree $Left $Right -NoColor
            $rows = @(Get-DifferenceRow $report)

            $rows.Count | Should -Be 3
            @($rows | Where-Object { $_ -like '<<*' }).Count | Should -Be 3
            Get-SummaryValue $report 'LEFT only:' | Should -Be 3
            Get-SummaryValue $report 'Ignored metadata differences:' | Should -Be 1
            Get-SummaryValue $report 'Relevant differences:' | Should -Be 2
        }
    }

    Context 'Scenario 10.10 - case-insensitive collision' {
        It 'fails clearly rather than guessing a match' {
            $enabled = $false
            try {
                $null = & fsutil.exe file setCaseSensitiveInfo $Left enable 2>&1
                $enabled = $LASTEXITCODE -eq 0
            }
            catch {
                $enabled = $false
            }

            if (-not $enabled) {
                Set-ItResult -Skipped -Because 'per-directory case sensitivity could not be enabled on this volume'
                return
            }

            New-TestFile (Join-Path $Left 'IMG_1001.JPG') 10
            New-TestFile (Join-Path $Left 'img_1001.jpg') 20

            { Compare-DirectoryTree $Left $Right -NoColor } | Should -Throw '*case-insensitive filename collision*'
        }
    }

    Context 'Scenario 10.11 - invalid, inaccessible, or unenumerable input' {
        It 'fails when a path does not exist' {
            { Compare-DirectoryTree (Join-Path $Left 'missing') $Right -NoColor } | Should -Throw '*Path not found*'
        }

        It 'fails when a path is a file rather than a directory' {
            $file = Join-Path $Left 'a.txt'
            New-TestFile $file 1

            { Compare-DirectoryTree $file $Right -NoColor } | Should -Throw '*not a directory*'
        }

        It 'fails and identifies the input when enumeration is denied' {
            $denied = Join-Path $Left 'denied'
            New-Item -ItemType Directory -Path $denied -Force | Out-Null

            $applied = $false
            try {
                $acl = Get-Acl -LiteralPath $denied
                $acl.SetAccessRuleProtection($true, $false)
                $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
                    'ListDirectory',
                    'None',
                    'None',
                    'Deny')
                $acl.AddAccessRule($rule)
                Set-Acl -LiteralPath $denied -AclObject $acl
                $null = [System.IO.DirectoryInfo]::new($denied).GetFiles()
            }
            catch [System.UnauthorizedAccessException] {
                $applied = $true
            }
            catch {
                $applied = $false
            }

            if (-not $applied) {
                Set-ItResult -Skipped -Because 'a deny ACL could not be applied in this environment'
                return
            }

            { Compare-DirectoryTree $Left $Right -Recurse -NoColor } | Should -Throw "*$denied*"
        }
    }

    Context 'Scenario 10.12 - verbose metadata explanation' {
        BeforeEach {
            New-TestFile (Join-Path $Left 'Thumbs.db') 1
            New-TestFile (Join-Path $Left '.DS_Store') 2
            New-TestFile (Join-Path $Right 'Thumbs.db') 3
            New-TestFile (Join-Path $Right '.DS_Store') 4
            New-TestFile (Join-Path $Left 'ehthumbs.db') 5
        }

        It 'explains each encountered metadata type exactly once' {
            $report = Compare-DirectoryTree $Left $Right -ExplainMetadata -NoColor

            @($report | Where-Object { $_ -like '*WIN-THUMBS*' }).Count | Should -Be 1
            @($report | Where-Object { $_ -like '*MAC-DSSTORE*' }).Count | Should -Be 1
            @($report | Where-Object { $_ -like '*WIN-EHTHUMBS*' }).Count | Should -Be 1
        }

        It 'does not describe catalog entries that were not encountered' {
            $report = Compare-DirectoryTree $Left $Right -ExplainMetadata -NoColor

            $report | Where-Object { $_ -like '*PHOTO-XMP*' } | Should -BeNullOrEmpty
            $report | Where-Object { $_ -like '*KDE-DIRECTORY*' } | Should -BeNullOrEmpty
        }

        It 'leaves the normal difference rows unchanged' {
            $plain = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -NoColor))
            $explained = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -ExplainMetadata -NoColor))

            $explained | Should -Be $plain
        }

        It 'omits the explanation section when -ExplainMetadata is not specified' {
            $report = Compare-DirectoryTree $Left $Right -NoColor

            $report | Where-Object { $_ -eq 'METADATA EXPLANATIONS' } | Should -BeNullOrEmpty
        }
    }

    Context 'Report model - Section 5 and Appendix B' {
        BeforeEach {
            New-TestFile (Join-Path $Left 'same.txt') 10
            New-TestFile (Join-Path $Right 'same.txt') 10
            New-TestFile (Join-Path $Left 'left-only.txt') 11
            New-TestFile (Join-Path $Right 'right-only.txt') 12
            New-TestFile (Join-Path $Left 'both.txt') 13
            New-TestFile (Join-Path $Right 'both.txt') 14
            $script:Report = Compare-DirectoryTree $Left $Right -NoColor
        }

        It 'maps the first argument to LEFT and the second to RIGHT' {
            $script:Report | Should -Contain "LEFT : $Left"
            $script:Report | Should -Contain "RIGHT: $Right"
        }

        It 'orders difference classes LEFT-only, RIGHT-only, then different' {
            $classes = @(Get-DifferenceRow $script:Report) | ForEach-Object { $_.Substring(0, 2) }
            $classes | Should -Be @('<<', '>>', '<>')
        }

        It 'separates non-empty difference classes with a blank line' {
            $rowIndexes = @(0..($script:Report.Count - 1) | Where-Object { $script:Report[$_] -match '^(<<|>>|<>)\s' })

            for ($i = 1; $i -lt $rowIndexes.Count; $i++) {
                $previous = $script:Report[$rowIndexes[$i - 1]].Substring(0, 2)
                $current = $script:Report[$rowIndexes[$i]].Substring(0, 2)
                if ($previous -ne $current) {
                    $script:Report[$rowIndexes[$i] - 1] | Should -Be ''
                }
            }
        }

        It 'produces no difference row for same-name, same-size pairs' {
            Get-DifferenceRow $script:Report | Should -Not -Match 'same\.txt'
        }

        It 'includes the legend and a single-line verdict' {
            $script:Report | Should -Contain 'Legend:'
            $script:Report | Should -Contain '  <<  Exists only on LEFT'
            $script:Report | Should -Contain '  >>  Exists only on RIGHT'
            $script:Report | Should -Contain '  <>  Same filename, different size'
            @($script:Report | Where-Object { $_ -like 'RESULT:*' }).Count | Should -Be 1
        }

        It 'emits every comparison entry on exactly one physical line' {
            foreach ($line in $script:Report) {
                $line | Should -Not -Match "[`r`n]"
            }
        }

        It 'describes the comparison rules up front' {
            $script:Report | Should -Contain 'Scope : Files in these directories only; subdirectories are NOT searched.'
            $script:Report | Should -Contain '        Hidden and system files ARE included.'
            $script:Report | Should -Contain 'Match : Filenames are compared case-insensitively.'
            $script:Report | Should -Contain 'Same  : Matching filename and exact size in bytes.'
        }

        It 'uses plain ASCII' {
            foreach ($line in $script:Report) {
                $line | Should -Not -Match '[^\x20-\x7E]'
            }
        }

        It 'never uses the unqualified word identical' {
            $script:Report | Should -Not -Match 'identical'
        }

        It 'formats sizes in exact bytes with thousands separators' {
            New-TestFile (Join-Path $Left 'big.bin') 1234567

            $report = Compare-DirectoryTree $Left $Right -NoColor
            Get-DifferenceRow $report | Where-Object { $_ -like '*big.bin*' } | Should -Match '1,234,567'
        }

        It 'does not truncate long filenames' {
            $longName = ('x' * 120) + '.txt'
            New-TestFile (Join-Path $Left $longName) 1

            $report = Compare-DirectoryTree $Left $Right -NoColor
            $report | Where-Object { $_ -like "*$longName*" } | Should -Not -BeNullOrEmpty
        }

        It 'sorts deterministically within a class' {
            foreach ($name in @('c.txt', 'a.txt', 'b.txt')) {
                New-TestFile (Join-Path $Left $name) 1
            }

            $first = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -NoColor) | Where-Object { $_ -like '<<*' })
            $second = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -NoColor) | Where-Object { $_ -like '<<*' })

            $first | Should -Be $second
            ($first -join "`n") | Should -Match '(?s)a\.txt.*b\.txt.*c\.txt'
        }

        It 'never modifies either input directory' {
            $beforeLeft = @(Get-FileSystemSnapshot $Left)
            $beforeRight = @(Get-FileSystemSnapshot $Right)

            Compare-DirectoryTree $Left $Right -NoColor -Recurse -ExplainMetadata | Out-Null

            @(Get-FileSystemSnapshot $Left) | Should -Be $beforeLeft
            @(Get-FileSystemSnapshot $Right) | Should -Be $beforeRight
        }

        It 'does not traverse subdirectories without -Recurse' {
            New-TestFile (Join-Path $Left 'sub\deep.txt') 99

            $report = Compare-DirectoryTree $Left $Right -NoColor

            Get-DifferenceRow $report | Should -Not -Match 'deep\.txt'
        }
    }

    Context 'Scenario 10.13 - recursive comparison' {
        BeforeEach {
            New-TestFile (Join-Path $Left 'Shared\same.txt') 10
            New-TestFile (Join-Path $Right 'Shared\same.txt') 10
            New-TestFile (Join-Path $Left 'Shared\diff.txt') 10
            New-TestFile (Join-Path $Right 'Shared\diff.txt') 11
            New-TestFile (Join-Path $Left 'Missing\a.bin') 100
            New-TestFile (Join-Path $Left 'Missing\Nested\b.bin') 200
            New-TestFile (Join-Path $Left 'Cache\Thumbs.db') 81920
            New-Item -ItemType Directory -Path (Join-Path $Left 'Empty\Deep') -Force | Out-Null
        }

        It 'collapses a fully missing subtree at the highest missing directory' {
            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -NoColor))

            ($rows | Where-Object { $_ -like '*[[]DIR[]] Missing\*' }) | Should -Be '<<  [DIR] Missing\   2 files, 1 dir, 300 B'
            $rows | Should -Not -Match 'Missing\\a\.bin'
            $rows | Should -Not -Match 'Missing\\Nested\\b\.bin'
        }

        It 'keeps a collapsed subtree summary and its ignored counts on one line' {
            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -NoColor))

            ($rows | Where-Object { $_ -like '*[[]DIR[]] Cache\*' }) | Should -Be '<<  [DIR] Cache\   1 file, 0 dirs, 81,920 B | ignored metadata 1'
        }

        It 'reports a one-sided empty directory as 0 files, 0 dirs, 0 B' {
            New-Item -ItemType Directory -Path (Join-Path $Right 'Solo') -Force | Out-Null
            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -NoColor))

            ($rows | Where-Object { $_ -like '*[[]DIR[]] Solo\*' }) | Should -Be '>>  [DIR] Solo\   0 files, 0 dirs, 0 B'
        }

        It 'does not silently omit nested empty-directory structure' {
            $report = Compare-DirectoryTree $Left $Right -Recurse -NoColor
            $rows = @(Get-DifferenceRow $report)

            ($rows | Where-Object { $_ -like '*[[]DIR[]] Empty\*' }) | Should -Be '<<  [DIR] Empty\   0 files, 1 dir, 0 B'
            Get-SummaryValue $report 'Empty-subdirectory differences:' | Should -Be 2
        }

        It 'reports file differences in shared directories individually with root-relative paths' {
            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -NoColor))

            ($rows | Where-Object { $_ -like '*Shared\diff.txt*' }) | Should -Match '^<>\s+Shared\\diff\.txt\s+10\s+11$'
        }

        It 'counts represented files rather than displayed rows' {
            $report = Compare-DirectoryTree $Left $Right -Recurse -NoColor

            Get-SummaryValue $report 'LEFT files:' | Should -Be 5
            Get-SummaryValue $report 'RIGHT files:' | Should -Be 2
            Get-SummaryValue $report 'LEFT only:' | Should -Be 3
            Get-SummaryValue $report 'Different size:' | Should -Be 1
            Get-SummaryValue $report 'Total differences:' | Should -Be 4
            Get-SummaryValue $report 'Ignored metadata differences:' | Should -Be 1
            Get-SummaryValue $report 'Relevant differences:' | Should -Be 3
            Get-SummaryValue $report 'LEFT-only directories:' | Should -Be 5
        }

        It 'keeps a metadata-only subtree visible without creating a relevant difference' {
            $pair = New-TestDirectoryPair
            try {
                New-TestFile (Join-Path $pair.Left 'Cache\Thumbs.db') 100

                $report = Compare-DirectoryTree $pair.Left $pair.Right -Recurse -NoColor
                $rows = @(Get-DifferenceRow $report)

                ($rows | Where-Object { $_ -like '*[[]DIR[]] Cache\*' }) | Should -Not -BeNullOrEmpty
                Get-SummaryValue $report 'Relevant differences:' | Should -Be 0
                Get-VerdictLine $report | Should -Be 'RESULT: SAME - qualified: differences limited to 1 ignored metadata file'
            }
            finally {
                Remove-Item -LiteralPath $pair.Base -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'contributes underlying relevant differences from a collapsed subtree' {
            $report = Compare-DirectoryTree $Left $Right -Recurse -NoColor

            Get-VerdictLine $report | Should -Be 'RESULT: NOT THE SAME - 3 relevant differences | 2 empty-subdirectory differences | 1 ignored metadata difference'
        }

        It 'summarizes shared directories per directory in -Compact mode' {
            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -Compact -NoColor))

            ($rows | Where-Object { $_ -like '*[[]DIR[]] Shared\*' }) | Should -Be '<>  [DIR] Shared\   1 same | << 0 | >> 0 | <> 1'
            $rows | Should -Not -Match 'Shared\\diff\.txt'
        }

        It 'does not recursively double-count descendant directories in -Compact mode' {
            New-TestFile (Join-Path $Left 'Shared\Deep\x.txt') 1
            New-TestFile (Join-Path $Right 'Shared\Deep\x.txt') 2

            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -Compact -NoColor))

            ($rows | Where-Object { $_ -like '*[[]DIR[]] Shared\ *' }) | Should -Be '<>  [DIR] Shared\   1 same | << 0 | >> 0 | <> 1'
            ($rows | Where-Object { $_ -like '*[[]DIR[]] Shared\Deep\*' }) | Should -Be '<>  [DIR] Shared\Deep\   0 same | << 0 | >> 0 | <> 1'
        }

        It 'retains collapsed one-sided subtree behavior in -Compact mode' {
            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -Compact -NoColor))

            ($rows | Where-Object { $_ -like '*[[]DIR[]] Missing\*' }) | Should -Be '<<  [DIR] Missing\   2 files, 1 dir, 300 B'
        }

        It 'reports one-sided subtree files individually with -ExpandMissingSubtrees' {
            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -ExpandMissingSubtrees -NoColor))

            ($rows | Where-Object { $_ -like '*Missing\a.bin*' }) | Should -Match '^<<\s+Missing\\a\.bin\s+100\s+<missing>$'
            ($rows | Where-Object { $_ -like '*Missing\Nested\b.bin*' }) | Should -Match '^<<\s+Missing\\Nested\\b\.bin\s+200\s+<missing>$'
        }

        It 'reports empty descendant directories explicitly with -ExpandMissingSubtrees' {
            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -ExpandMissingSubtrees -NoColor))

            ($rows | Where-Object { $_ -like '*[[]DIR[]] Empty\*' }) | Should -Be '<<  [DIR] Empty\   0 files, 1 dir, 0 B'
        }

        It 'does not emit redundant non-empty ancestor rows with -ExpandMissingSubtrees' {
            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -ExpandMissingSubtrees -NoColor))

            $rows | Where-Object { $_ -like '*[[]DIR[]] Missing\*' } | Should -BeNullOrEmpty
        }

        It 'keeps summary counts identical across recursive presentation modes' {
            $default = Compare-DirectoryTree $Left $Right -Recurse -NoColor
            $compact = Compare-DirectoryTree $Left $Right -Recurse -Compact -NoColor
            $expanded = Compare-DirectoryTree $Left $Right -Recurse -ExpandMissingSubtrees -NoColor

            foreach ($label in @('LEFT files:', 'RIGHT files:', 'Same:', 'Different size:', 'LEFT only:', 'RIGHT only:', 'Total differences:', 'Ignored metadata differences:', 'Relevant differences:', 'Empty-subdirectory differences:')) {
                Get-SummaryValue $compact $label | Should -Be (Get-SummaryValue $default $label)
                Get-SummaryValue $expanded $label | Should -Be (Get-SummaryValue $default $label)
            }

            Get-VerdictLine $compact | Should -Be (Get-VerdictLine $default)
            Get-VerdictLine $expanded | Should -Be (Get-VerdictLine $default)
        }

        It 'matches root-relative paths case-insensitively' {
            $pair = New-TestDirectoryPair
            try {
                New-TestFile (Join-Path $pair.Left 'Sub\File.TXT') 5
                New-TestFile (Join-Path $pair.Right 'SUB\file.txt') 5

                $report = Compare-DirectoryTree $pair.Left $pair.Right -Recurse -NoColor

                Get-SummaryValue $report 'Same:' | Should -Be 1
                Get-SummaryValue $report 'Total differences:' | Should -Be 0
            }
            finally {
                Remove-Item -LiteralPath $pair.Base -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'qualifies a SAME verdict when only empty directories differ' {
            $pair = New-TestDirectoryPair
            try {
                New-Item -ItemType Directory -Path (Join-Path $pair.Left 'OnlyHere') -Force | Out-Null

                $report = Compare-DirectoryTree $pair.Left $pair.Right -Recurse -NoColor

                Get-SummaryValue $report 'Relevant differences:' | Should -Be 0
                Get-VerdictLine $report | Should -Be 'RESULT: SAME - qualified: different empty subdirectories'
            }
            finally {
                Remove-Item -LiteralPath $pair.Base -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'qualifies a SAME verdict when structure and ignorable metadata both differ' {
            $pair = New-TestDirectoryPair
            try {
                New-Item -ItemType Directory -Path (Join-Path $pair.Left 'OnlyHere') -Force | Out-Null
                New-TestFile (Join-Path $pair.Left 'Thumbs.db') 10

                $report = Compare-DirectoryTree $pair.Left $pair.Right -Recurse -NoColor

                Get-VerdictLine $report | Should -Be 'RESULT: SAME - qualified: different empty subdirectories; other differences limited to ignorable metadata'
            }
            finally {
                Remove-Item -LiteralPath $pair.Base -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'describes the recursive scope and presentation mode in the header' {
            $default = Compare-DirectoryTree $Left $Right -Recurse -NoColor
            $compact = Compare-DirectoryTree $Left $Right -Recurse -Compact -NoColor
            $expanded = Compare-DirectoryTree $Left $Right -Recurse -ExpandMissingSubtrees -NoColor

            $default | Should -Contain 'Scope : All files beneath these directories; subdirectories ARE searched.'
            $default | Should -Contain '        Presentation: one-sided subtrees collapsed at the highest missing directory.'
            $compact | Should -Contain '        Presentation: compact directory summaries.'
            $expanded | Should -Contain '        Presentation: one-sided subtrees expanded file by file.'
        }

        It 'rejects combined and unsupported presentation switches' {
            { Compare-DirectoryTree $Left $Right -Recurse -Compact -ExpandMissingSubtrees -NoColor } | Should -Throw '*cannot be combined*'
            { Compare-DirectoryTree $Left $Right -Compact -NoColor } | Should -Throw '*-Compact requires -Recurse*'
            { Compare-DirectoryTree $Left $Right -ExpandMissingSubtrees -NoColor } | Should -Throw '*-ExpandMissingSubtrees requires -Recurse*'
        }

        It 'keeps every recursive entry on one physical line' {
            foreach ($mode in @(@{}, @{ Compact = $true }, @{ ExpandMissingSubtrees = $true })) {
                $report = Compare-DirectoryTree $Left $Right -Recurse -NoColor @mode
                foreach ($line in $report) {
                    $line | Should -Not -Match "[`r`n]"
                }
            }
        }

        It 'accounts for every observed filesystem object' {
            $report = Compare-DirectoryTree $Left $Right -Recurse -NoColor

            $actualLeftFiles = @(Get-ChildItem -LiteralPath $Left -Recurse -File -Force).Count
            $actualRightFiles = @(Get-ChildItem -LiteralPath $Right -Recurse -File -Force).Count

            Get-SummaryValue $report 'LEFT files:' | Should -Be $actualLeftFiles
            Get-SummaryValue $report 'RIGHT files:' | Should -Be $actualRightFiles
            (Get-SummaryValue $report 'Same:') + (Get-SummaryValue $report 'Different size:') + (Get-SummaryValue $report 'LEFT only:') | Should -Be $actualLeftFiles
        }
    }

    Context 'Scenario 10.14 - console color' {
        BeforeEach {
            New-TestFile (Join-Path $Left 'left-only.txt') 1
            New-TestFile (Join-Path $Right 'right-only.txt') 2
            New-TestFile (Join-Path $Left 'both.txt') 3
            New-TestFile (Join-Path $Right 'both.txt') 4
            New-TestFile (Join-Path $Left 'Thumbs.db') 5
            $script:Plain = Compare-DirectoryTree $Left $Right -NoColor
            $script:Colored = @(Add-CDTColor -Line $script:Plain)
            $script:Escape = [char]27
        }

        It 'colors the LEFT, RIGHT, and different markers distinctly' {
            $leftRow = $script:Colored | Where-Object { $_ -like '*left-only.txt*' }
            $rightRow = $script:Colored | Where-Object { $_ -like '*right-only.txt*' }
            $diffRow = $script:Colored | Where-Object { $_ -like '*both.txt*' }

            $leftRow.StartsWith("$script:Escape[36m<<$script:Escape[0m") | Should -BeTrue
            $rightRow.StartsWith("$script:Escape[35m>>$script:Escape[0m") | Should -BeTrue
            $diffRow.StartsWith("$script:Escape[33m<>$script:Escape[0m") | Should -BeTrue
        }

        It 'colors only the two-character marker on an ordinary row' {
            $row = $script:Colored | Where-Object { $_ -like '*left-only.txt*' }
            $body = $row.Substring("$script:Escape[36m<<$script:Escape[0m".Length)

            $body | Should -Not -Match ([regex]::Escape($script:Escape))
        }

        It 'dims Ignored annotations while keeping the directional marker color' {
            $row = $script:Colored | Where-Object { $_ -like '*Thumbs.db*' }

            $row.StartsWith("$script:Escape[36m<<$script:Escape[0m") | Should -BeTrue
            $row.EndsWith("$script:Escape[2mIgnored: Windows thumbnail cache$script:Escape[0m") | Should -BeTrue
        }

        It 'colors only the verdict phrase' {
            $notSame = Add-CDTColor -Line @('RESULT: NOT THE SAME - 2 relevant differences | 1 ignored metadata difference')
            $same = Add-CDTColor -Line @('RESULT: SAME - all 3 files match')

            $notSame | Should -Be "RESULT: $script:Escape[31mNOT THE SAME$script:Escape[0m - 2 relevant differences | 1 ignored metadata difference"
            $same | Should -Be "RESULT: $script:Escape[32mSAME$script:Escape[0m - all 3 files match"
        }

        It 'does not color ordinary difference rows red' {
            foreach ($row in ($script:Colored | Where-Object { $_ -notlike 'RESULT:*' })) {
                $row | Should -Not -Match ([regex]::Escape("$script:Escape[31m"))
            }
        }

        It 'does not give structural rows an additional color' {
            $pair = New-TestDirectoryPair
            try {
                New-Item -ItemType Directory -Path (Join-Path $pair.Left 'OnlyHere') -Force | Out-Null
                $colored = @(Add-CDTColor -Line (Compare-DirectoryTree $pair.Left $pair.Right -Recurse -NoColor))

                ($colored | Where-Object { $_ -like '*[[]DIR[]] OnlyHere\*' }) | Should -Be "$script:Escape[36m<<$script:Escape[0m  [DIR] OnlyHere\   0 files, 0 dirs, 0 B"
            }
            finally {
                Remove-Item -LiteralPath $pair.Base -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'produces identical text, ordering, and spacing once color is stripped' {
            $stripped = $script:Colored | ForEach-Object { $_ -replace "$script:Escape\[\d+m", '' }

            $stripped | Should -Be $script:Plain
        }

        It 'does not add lines or a color legend' {
            $script:Colored.Count | Should -Be @($script:Plain).Count
            $script:Colored | Where-Object { $_ -like '*cyan*' -or $_ -like '*magenta*' -or $_ -like '*yellow*' } | Should -BeNullOrEmpty
        }

        It 'emits no escape sequences with -NoColor' {
            $script:Plain | Should -Not -Match ([regex]::Escape($script:Escape))
        }

        It 'emits no escape sequences when output is redirected' {
            $shell = (Get-Process -Id $PID).Path
            $output = & $shell -NoProfile -File $script:ScriptPath $Left $Right

            $output | Should -Not -BeNullOrEmpty
            $output | Should -Not -Match ([regex]::Escape($script:Escape))
        }

        It 'remains understandable without color' {
            $script:Plain | Should -Contain '  <<  Exists only on LEFT'
            ($script:Plain | Where-Object { $_ -like '*Thumbs.db*' }) | Should -Match 'Ignored:'
            Get-VerdictLine $script:Plain | Should -BeLike '*NOT THE SAME*'
        }
    }
}
