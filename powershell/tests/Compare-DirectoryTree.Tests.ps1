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

    function Get-CollapsedRow {
        param(
            [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]] $Report,
            [Parameter(Mandatory)][string] $Match
        )

        $Report |
            Where-Object { $_ -match '^(<<|>>|<>)\s' } |
            ForEach-Object { ($_ -replace '\s+', ' ').Trim() } |
            Where-Object { $_ -like $Match }
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
        It 'reports MATCH with no differences' {
            New-TestFile (Join-Path $Left 'IMG_1001.JPG') 5000
            New-TestFile (Join-Path $Left 'IMG_1002.JPG') 6000
            New-TestFile (Join-Path $Right 'IMG_1001.JPG') 5000
            New-TestFile (Join-Path $Right 'IMG_1002.JPG') 6000

            $report = Compare-DirectoryTree $Left $Right -NoColor

            Get-SummaryValue $report 'Same:' | Should -Be 2
            Get-SummaryValue $report 'Total differences:' | Should -Be 0
            Get-SummaryValue $report 'Relevant differences:' | Should -Be 0
            Get-VerdictLine $report | Should -Be 'RESULT: MATCH - all 2 files match'
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
            Get-VerdictLine $report | Should -Be 'RESULT: DIFFERENT - 1 relevant difference'
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
            Get-VerdictLine $report | Should -Be 'RESULT: MATCH - qualified: differences limited to 1 ignored metadata file'
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
            Get-VerdictLine $report | Should -BeLike 'RESULT: DIFFERENT*'
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
        It 'reports MATCH with zero counts' {
            $report = Compare-DirectoryTree $Left $Right -NoColor

            Get-SummaryValue $report 'LEFT files:' | Should -Be 0
            Get-SummaryValue $report 'RIGHT files:' | Should -Be 0
            Get-SummaryValue $report 'Total differences:' | Should -Be 0
            Get-SummaryValue $report 'Relevant differences:' | Should -Be 0
            Get-VerdictLine $report | Should -Be 'RESULT: MATCH - all 0 files match'
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

    Context 'Scenario 10.17 - control characters in names' {
        It 'escapes every control character in a rendered name' {
            $name = 'IMG' + [char]27 + '[32m' + [char]10 + [char]0 + [char]127 + '.JPG'

            Format-CDTSafeName -Name $name | Should -Be 'IMG<0x1B>[32m<0x0A><0x00><0x7F>.JPG'
        }

        It 'rejects every ASCII control character' {
            foreach ($code in @(0..31) + @(127)) {
                $thrown = $false
                try { Assert-CDTNameSafe -Name ('a' + [char]$code + 'b') -Side 'LEFT' } catch { $thrown = $true }
                $thrown | Should -BeTrue -Because "0x$('{0:X2}' -f $code) must be rejected"
            }
        }

        It 'accepts ordinary names and C1 code points' {
            { Assert-CDTNameSafe -Name 'IMG_1901.JPG' -Side 'LEFT' } | Should -Not -Throw
            { Assert-CDTNameSafe -Name ('Dad' + [char]0x92 + 's photos.jpg') -Side 'LEFT' } | Should -Not -Throw
            Format-CDTSafeName -Name ('Dad' + [char]0x92 + 's.jpg') | Should -Be ('Dad' + [char]0x92 + 's.jpg')
        }

        It 'names the side, the escaped name, and the offending character' {
            $message = $null
            try {
                Assert-CDTNameSafe -Name ('IMG_1901' + [char]27 + '[32m.JPG') -Side 'RIGHT'
            }
            catch {
                $message = $_.Exception.Message
            }

            $message | Should -Be "Illegal name on RIGHT: 'IMG_1901<0x1B>[32m.JPG' contains ASCII control character 0x1B"
            $message.Contains([char]27) | Should -BeFalse
            @($message -split "`n").Count | Should -Be 1
        }

        It 'identifies a nested offender by its root-relative path' {
            $message = $null
            try {
                Assert-CDTNameSafe -Name ('IMG_1901' + [char]27 + '.JPG') -Side 'LEFT' -Container '2018\Camp'
            }
            catch {
                $message = $_.Exception.Message
            }

            $message | Should -Be "Illegal name on LEFT: '2018\Camp\IMG_1901<0x1B>.JPG' contains ASCII control character 0x1B"
        }

        It 'rejects a supplied path containing a control character without echoing it' {
            foreach ($side in 'LEFT', 'RIGHT') {
                $bad = Join-Path $Left ('evil' + [char]27 + '[32mdir')
                $message = $null
                try {
                    if ($side -eq 'LEFT') {
                        Compare-DirectoryTree $bad $Right -NoColor
                    }
                    else {
                        Compare-DirectoryTree $Left $bad -NoColor
                    }
                }
                catch {
                    $message = $_.Exception.Message
                }

                $message | Should -BeLike "Illegal name on $side*"
                $message.Contains([char]27) | Should -BeFalse
            }
        }

        It 'fails when an in-scope file name contains a control character' {
            $name = 'IMG_1901' + [char]27 + '[32m.JPG'
            $path = Join-Path $Left $name
            $created = $false
            try {
                $stream = [System.IO.File]::Create($path)
                $stream.Dispose()
                $created = Test-Path -LiteralPath $path
            }
            catch {
                $created = $false
            }

            if (-not $created) {
                Set-ItResult -Skipped -Because 'this filesystem does not permit control characters in a file name'
                return
            }

            $message = $null
            try { Compare-DirectoryTree $Left $Right -NoColor } catch { $message = $_.Exception.Message }

            $message | Should -Be "Illegal name on LEFT: 'IMG_1901<0x1B>[32m.JPG' contains ASCII control character 0x1B"
        }

        It 'fails when an in-scope directory name contains a control character under -Recurse' {
            $name = 'Camp' + [char]10 + 'Raw'
            $path = Join-Path $Right $name
            $created = $false
            try {
                New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
                $created = Test-Path -LiteralPath $path
            }
            catch {
                $created = $false
            }

            if (-not $created) {
                Set-ItResult -Skipped -Because 'this filesystem does not permit control characters in a directory name'
                return
            }

            $message = $null
            try { Compare-DirectoryTree $Left $Right -Recurse -NoColor } catch { $message = $_.Exception.Message }

            $message | Should -Be "Illegal name on RIGHT: 'Camp<0x0A>Raw' contains ASCII control character 0x0A"
        }

        It 'does not examine out-of-scope subdirectory names without -Recurse' {
            $name = 'Camp' + [char]10 + 'Raw'
            $path = Join-Path $Left $name
            $created = $false
            try {
                New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
                $created = Test-Path -LiteralPath $path
            }
            catch {
                $created = $false
            }

            if (-not $created) {
                Set-ItResult -Skipped -Because 'this filesystem does not permit control characters in a directory name'
                return
            }

            $report = Compare-DirectoryTree $Left $Right -NoColor

            Get-VerdictLine $report | Should -Be 'RESULT: MATCH - all 0 files match'
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
            $script:Report | Should -Contain '  <<   Exists only on LEFT'
            $script:Report | Should -Contain '  >>   Exists only on RIGHT'
            $script:Report | Should -Contain '  <>   Same filename, different size'
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

    Context 'Scenario 10.15 - verdict vocabulary and Type column' {
        BeforeEach {
            foreach ($name in @('one.txt', 'two.txt')) {
                New-TestFile (Join-Path $Left $name) 10
                New-TestFile (Join-Path $Right $name) 10
            }
        }

        It 'writes MATCH for a positive verdict and DIFFERENT for a negative one' {
            $match = Compare-DirectoryTree $Left $Right -NoColor
            New-TestFile (Join-Path $Left 'extra.txt') 1
            $different = Compare-DirectoryTree $Left $Right -NoColor

            Get-VerdictLine $match | Should -Be 'RESULT: MATCH - all 2 files match'
            Get-VerdictLine $different | Should -Be 'RESULT: DIFFERENT - 1 relevant difference'
        }

        It 'keeps an exact search for RESULT: MATCH from matching a negative verdict' {
            New-TestFile (Join-Path $Left 'extra.txt') 1
            $report = Compare-DirectoryTree $Left $Right -NoColor

            $report | Where-Object { $_.Contains('RESULT: MATCH') } | Should -BeNullOrEmpty
            $report | Should -Not -Match 'NOT THE SAME'
        }

        It 'retains per-file same wording in the summary, header, and compact rows' {
            $report = Compare-DirectoryTree $Left $Right -NoColor

            $report | Should -Contain 'Same  : Matching filename and exact size in bytes.'
            Get-SummaryValue $report 'Same:' | Should -Be 2

            New-TestFile (Join-Path $Left 'Sub\a.txt') 1
            New-TestFile (Join-Path $Right 'Sub\a.txt') 2
            $compact = Compare-DirectoryTree $Left $Right -Recurse -Compact -NoColor
            Get-CollapsedRow $compact '*Sub\*' | Should -Match '0 same '
        }

        It 'heads the table with Type and File / Directory' {
            New-TestFile (Join-Path $Left 'extra.txt') 1
            $report = Compare-DirectoryTree $Left $Right -NoColor

            ($report | Where-Object { $_ -like '*Type*File / Directory*' }) | Should -Not -BeNullOrEmpty
        }

        It 'writes DIR for directory rows, leaves file rows blank, and never writes FILE' {
            New-TestFile (Join-Path $Left 'extra.txt') 1
            New-Item -ItemType Directory -Path (Join-Path $Left 'OnlyHere') -Force | Out-Null
            $report = Compare-DirectoryTree $Left $Right -Recurse -NoColor
            $rows = @(Get-DifferenceRow $report)

            ($rows | Where-Object { $_ -like '*OnlyHere\*' }) | Should -Match '^<<  DIR   '
            ($rows | Where-Object { $_ -like '*extra.txt*' }) | Should -Match '^<<        '
            $rows | ForEach-Object { $_.Substring(4, 4) } | Should -Not -Be 'FILE'
            $report | Should -Not -Match '\[DIR\]'
        }

        It 'begins directory paths and file paths in the same column' {
            New-TestFile (Join-Path $Left 'extra.txt') 1
            New-Item -ItemType Directory -Path (Join-Path $Left 'OnlyHere') -Force | Out-Null
            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -NoColor))

            foreach ($row in $rows) {
                $row.IndexOf($row.Trim().Split(' ')[-1]) | Should -BeGreaterThan 0
                $row.Substring(0, 10) | Should -Match '^(<<|>>|<>)  (DIR |    )  $'
            }
        }
    }

    Context 'Scenario 10.16 - report formatting determinism' {
        It 'abbreviates directory-summary byte totals but never file sizes' {
            New-TestFile (Join-Path $Left 'Cache\big.bin') 81920
            New-Item -ItemType Directory -Path (Join-Path $Left 'Empty') -Force | Out-Null
            New-TestFile (Join-Path $Left 'plain.bin') 81920

            $report = Compare-DirectoryTree $Left $Right -Recurse -NoColor

            Get-CollapsedRow $report '*Cache\*' | Should -Be '<< DIR Cache\ 1 file, 0 dirs, 80 KB'
            Get-CollapsedRow $report '*Empty\*' | Should -Be '<< DIR Empty\ 0 files, 0 dirs, 0 B'
            Get-CollapsedRow $report '*plain.bin*' | Should -Be '<< plain.bin 81,920 <missing>'
        }

        It 'formats aggregate byte totals per Section 5.3' {
            Format-CDTAggregateByteTotal -Bytes 0 | Should -Be '0 B'
            Format-CDTAggregateByteTotal -Bytes 81 | Should -Be '81 B'
            Format-CDTAggregateByteTotal -Bytes 1023 | Should -Be '1023 B'
            Format-CDTAggregateByteTotal -Bytes 1024 | Should -Be '1 KB'
            Format-CDTAggregateByteTotal -Bytes 81920 | Should -Be '80 KB'
            Format-CDTAggregateByteTotal -Bytes 8375186227 | Should -Be '7.8 GB'
        }

        It 'begins a directory-summary row text in the LEFT size column' {
            New-Item -ItemType Directory -Path (Join-Path $Left 'Empty') -Force | Out-Null
            $report = Compare-DirectoryTree $Left $Right -Recurse -NoColor

            $header = $report | Where-Object { $_ -like '*LEFT size (bytes)*' } | Select-Object -First 1
            $row = $report | Where-Object { $_ -like '*DIR   Empty\*' } | Select-Object -First 1

            $row.IndexOf('0 files') | Should -Be ($header.IndexOf('LEFT size (bytes)'))
        }

        It 'interleaves directory rows and file rows in one path ordering' {
            New-TestFile (Join-Path $Right 'Camp\anchor.txt') 1
            New-TestFile (Join-Path $Left 'Camp\anchor.txt') 1
            New-Item -ItemType Directory -Path (Join-Path $Left 'Camp\Empty') -Force | Out-Null
            New-TestFile (Join-Path $Left 'Camp\IMG.JPG') 1
            New-TestFile (Join-Path $Left 'Camp\Raw\a.cr2') 1
            New-TestFile (Join-Path $Left 'Camp\Thumbs.db') 1

            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -NoColor) | Where-Object { $_ -like '<<*' })
            $paths = @($rows | ForEach-Object { ($_ -replace '\s+', ' ').Split(' ') | Where-Object { $_ -like 'Camp\*' } })

            $paths | Should -Be @('Camp\Empty\', 'Camp\IMG.JPG', 'Camp\Raw\', 'Camp\Thumbs.db')
        }

        It 'orders paths segment by segment rather than as whole strings' {
            New-TestFile (Join-Path $Left 'a\b.txt') 1
            New-TestFile (Join-Path $Left 'a.txt') 1

            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -ExpandMissingSubtrees -NoColor) | Where-Object { $_ -like '<<*' })

            ($rows -join "`n") | Should -Match '(?s)a\\b\.txt.*a\.txt'
        }

        It 'includes the DIR legend line only when a directory-summary row is present' {
            New-TestFile (Join-Path $Left 'extra.txt') 1
            $withoutDir = Compare-DirectoryTree $Left $Right -NoColor

            New-Item -ItemType Directory -Path (Join-Path $Left 'Empty') -Force | Out-Null
            $withDir = Compare-DirectoryTree $Left $Right -Recurse -NoColor

            $withoutDir | Should -Not -Contain '  DIR  Directory summary row'
            $withDir | Should -Contain '  DIR  Directory summary row'
        }

        It 'always lists the three difference markers even when a class has no rows' {
            New-TestFile (Join-Path $Left 'only-left.txt') 1
            $report = Compare-DirectoryTree $Left $Right -NoColor

            Get-DifferenceRow $report | Should -Not -Match '^(>>|<>)'
            $report | Should -Contain '  <<   Exists only on LEFT'
            $report | Should -Contain '  >>   Exists only on RIGHT'
            $report | Should -Contain '  <>   Same filename, different size'
        }

        It 'omits the DIFFERENCES section entirely when there are no difference rows' {
            $report = Compare-DirectoryTree $Left $Right -Recurse -NoColor

            $report | Should -Not -Contain 'DIFFERENCES'
            $report | Should -Not -Contain 'Legend:'
            $report | Where-Object { $_ -like '*File / Directory*' } | Should -BeNullOrEmpty
        }

        It 'switches the legend wording for the difference marker with -Recurse' {
            New-TestFile (Join-Path $Left 'diff.txt') 1
            New-TestFile (Join-Path $Right 'diff.txt') 2

            (Compare-DirectoryTree $Left $Right -NoColor) | Should -Contain '  <>   Same filename, different size'
            (Compare-DirectoryTree $Left $Right -Recurse -NoColor) | Should -Contain '  <>   Same relative path, different size'
        }

        It 'includes the directory block and Structural differences only under -Recurse' {
            New-Item -ItemType Directory -Path (Join-Path $Left 'Empty') -Force | Out-Null

            $flat = Compare-DirectoryTree $Left $Right -NoColor
            $recursive = Compare-DirectoryTree $Left $Right -Recurse -NoColor

            $flat | Should -Not -Match '^(LEFT directories:|Structural differences:)'
            foreach ($label in @('LEFT directories:', 'RIGHT directories:', 'LEFT-only directories:', 'RIGHT-only directories:', 'Empty-directory differences:', 'Structural differences:')) {
                $recursive | Where-Object { $_ -like "$label*" } | Should -Not -BeNullOrEmpty
            }
        }

        It 'does not fold Empty-directory differences into Structural differences' {
            New-Item -ItemType Directory -Path (Join-Path $Left 'Empty') -Force | Out-Null
            New-TestFile (Join-Path $Left 'Full\a.txt') 1

            $report = Compare-DirectoryTree $Left $Right -Recurse -NoColor

            Get-SummaryValue $report 'LEFT-only directories:' | Should -Be 2
            Get-SummaryValue $report 'Empty-directory differences:' | Should -Be 1
            Get-SummaryValue $report 'Structural differences:' | Should -Be 2
        }

        It 'keeps structural differences out of the file difference counters' {
            New-Item -ItemType Directory -Path (Join-Path $Left 'Empty') -Force | Out-Null
            $report = Compare-DirectoryTree $Left $Right -Recurse -NoColor

            Get-SummaryValue $report 'Total differences:' | Should -Be 0
            Get-SummaryValue $report 'Ignored metadata differences:' | Should -Be 0
            Get-SummaryValue $report 'Relevant differences:' | Should -Be 0
        }

        It 'orders verdict segments and omits zero-valued ones' {
            New-TestFile (Join-Path $Left 'extra.txt') 1
            New-TestFile (Join-Path $Left 'Thumbs.db') 1
            New-Item -ItemType Directory -Path (Join-Path $Left 'Empty') -Force | Out-Null
            New-TestFile (Join-Path $Left 'Full\a.txt') 1

            $verdict = Get-VerdictLine (Compare-DirectoryTree $Left $Right -Recurse -NoColor)

            $verdict | Should -Be 'RESULT: DIFFERENT - 2 relevant differences | 1 empty-subdirectory difference | 1 directory-structure difference | 1 ignored metadata difference'
            $verdict | Should -Not -Match '\| 0 '
        }

        It 'sums the two structural verdict segments to Structural differences' {
            New-TestFile (Join-Path $Left 'extra.txt') 1
            New-Item -ItemType Directory -Path (Join-Path $Left 'Empty') -Force | Out-Null
            New-TestFile (Join-Path $Left 'Full\Deep\a.txt') 1

            $report = Compare-DirectoryTree $Left $Right -Recurse -NoColor
            $verdict = Get-VerdictLine $report

            $empty = [int]([regex]::Match($verdict, '(\d+) empty-subdirectory').Groups[1].Value)
            $structure = [int]([regex]::Match($verdict, '(\d+) directory-structure').Groups[1].Value)

            ($empty + $structure) | Should -Be (Get-SummaryValue $report 'Structural differences:')
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

            Get-CollapsedRow $rows '*Missing\*' | Should -Be '<< DIR Missing\ 2 files, 1 dir, 300 B'
            $rows | Should -Not -Match 'Missing\\a\.bin'
            $rows | Should -Not -Match 'Missing\\Nested\\b\.bin'
        }

        It 'keeps a collapsed subtree summary and its ignored counts on one line' {
            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -NoColor))

            Get-CollapsedRow $rows '*Cache\*' | Should -Be '<< DIR Cache\ 1 file, 0 dirs, 80 KB | ignored metadata 1'
        }

        It 'reports a one-sided empty directory as 0 files, 0 dirs, 0 B' {
            New-Item -ItemType Directory -Path (Join-Path $Right 'Solo') -Force | Out-Null
            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -NoColor))

            Get-CollapsedRow $rows '*Solo\*' | Should -Be '>> DIR Solo\ 0 files, 0 dirs, 0 B'
        }

        It 'does not silently omit nested empty-directory structure' {
            $report = Compare-DirectoryTree $Left $Right -Recurse -NoColor
            $rows = @(Get-DifferenceRow $report)

            Get-CollapsedRow $rows '*Empty\*' | Should -Be '<< DIR Empty\ 0 files, 1 dir, 0 B'
            Get-SummaryValue $report 'Empty-directory differences:' | Should -Be 1
            Get-SummaryValue $report 'Structural differences:' | Should -Be 5
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

                Get-CollapsedRow $rows '*Cache\*' | Should -Not -BeNullOrEmpty
                Get-SummaryValue $report 'Relevant differences:' | Should -Be 0
                Get-VerdictLine $report | Should -Be 'RESULT: MATCH - qualified: directory structure differs; other differences limited to ignorable metadata'
            }
            finally {
                Remove-Item -LiteralPath $pair.Base -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'contributes underlying relevant differences from a collapsed subtree' {
            $report = Compare-DirectoryTree $Left $Right -Recurse -NoColor

            Get-VerdictLine $report | Should -Be 'RESULT: DIFFERENT - 3 relevant differences | 1 empty-subdirectory difference | 4 directory-structure differences | 1 ignored metadata difference'
        }

        It 'summarizes shared directories per directory in -Compact mode' {
            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -Compact -NoColor))

            Get-CollapsedRow $rows '*Shared\*' | Should -Be '<> DIR Shared\ 1 same | << 0 | >> 0 | <> 1'
            $rows | Should -Not -Match 'Shared\\diff\.txt'
        }

        It 'does not recursively double-count descendant directories in -Compact mode' {
            New-TestFile (Join-Path $Left 'Shared\Deep\x.txt') 1
            New-TestFile (Join-Path $Right 'Shared\Deep\x.txt') 2

            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -Compact -NoColor))

            Get-CollapsedRow $rows '*Shared\ *' | Should -Be '<> DIR Shared\ 1 same | << 0 | >> 0 | <> 1'
            Get-CollapsedRow $rows '*Shared\Deep\*' | Should -Be '<> DIR Shared\Deep\ 0 same | << 0 | >> 0 | <> 1'
        }

        It 'retains collapsed one-sided subtree behavior in -Compact mode' {
            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -Compact -NoColor))

            Get-CollapsedRow $rows '*Missing\*' | Should -Be '<< DIR Missing\ 2 files, 1 dir, 300 B'
        }

        It 'renders the compared roots as .\ in a -Compact directory summary row' {
            $pair = New-TestDirectoryPair
            try {
                New-TestFile (Join-Path $pair.Left 'rootonly.bin') 100
                New-TestFile (Join-Path $pair.Left 'Sub\a.bin') 50

                $rows = @(Get-DifferenceRow (Compare-DirectoryTree $pair.Left $pair.Right -Recurse -Compact -NoColor))
                $root = @($rows | ForEach-Object { ($_ -replace '\s+', ' ').Trim() } | Where-Object { $_ -like '*DIR .\*' })

                $root.Count | Should -Be 1
                $root[0] | Should -Match '^<> DIR \.\\ '
            } finally {
                Remove-Item -LiteralPath $pair.Base -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'reports one-sided subtree files individually with -ExpandMissingSubtrees' {
            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -ExpandMissingSubtrees -NoColor))

            ($rows | Where-Object { $_ -like '*Missing\a.bin*' }) | Should -Match '^<<\s+Missing\\a\.bin\s+100\s+<missing>$'
            ($rows | Where-Object { $_ -like '*Missing\Nested\b.bin*' }) | Should -Match '^<<\s+Missing\\Nested\\b\.bin\s+200\s+<missing>$'
        }

        It 'reports empty descendant directories explicitly with -ExpandMissingSubtrees' {
            New-TestFile (Join-Path $Left 'Raw\top.jpg') 100
            New-Item -ItemType Directory -Path (Join-Path $Left 'Raw\X\Y'), (Join-Path $Left 'Raw\X\Z') -Force | Out-Null

            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -ExpandMissingSubtrees -NoColor))

            Get-CollapsedRow $rows '*Raw\X\Y\*' | Should -Be '<< DIR Raw\X\Y\ 0 files, 0 dirs, 0 B'
            Get-CollapsedRow $rows '*Raw\X\Z\*' | Should -Be '<< DIR Raw\X\Z\ 0 files, 0 dirs, 0 B'
            Get-CollapsedRow $rows '*DIR Empty\Deep\*' | Should -Be '<< DIR Empty\Deep\ 0 files, 0 dirs, 0 B'
        }

        It 'does not emit container or ancestor rows with -ExpandMissingSubtrees' {
            New-TestFile (Join-Path $Left 'Raw\top.jpg') 100
            New-Item -ItemType Directory -Path (Join-Path $Left 'Raw\X\Y') -Force | Out-Null

            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -ExpandMissingSubtrees -NoColor))

            Get-CollapsedRow $rows '<< DIR Missing\' | Should -BeNullOrEmpty
            Get-CollapsedRow $rows '<< DIR Raw\' | Should -BeNullOrEmpty
            Get-CollapsedRow $rows '<< DIR Raw\X\' | Should -BeNullOrEmpty
            Get-CollapsedRow $rows '<< DIR Empty\' | Should -BeNullOrEmpty
        }

        It 'orders empty-directory rows with file rows by segment in -ExpandMissingSubtrees mode' {
            New-TestFile (Join-Path $Left 'Raw\IMG_1001.JPG') 100
            New-TestFile (Join-Path $Left 'Raw\Nested\IMG_1002.JPG') 200
            New-Item -ItemType Directory -Path (Join-Path $Left 'Raw\Empty') -Force | Out-Null

            $rows = @(Get-DifferenceRow (Compare-DirectoryTree $Left $Right -Recurse -ExpandMissingSubtrees -NoColor))
            $raw = @($rows | ForEach-Object { ($_ -replace '\s+', ' ').Trim() } | Where-Object { $_ -like '*Raw\*' })

            $raw.Count | Should -Be 3
            $raw[0] | Should -Be '<< DIR Raw\Empty\ 0 files, 0 dirs, 0 B'
            $raw[1] | Should -Match '^<< Raw\\IMG_1001\.JPG 100 '
            $raw[2] | Should -Match '^<< Raw\\Nested\\IMG_1002\.JPG 200 '
        }

        It 'keeps summary counts identical across recursive presentation modes' {
            $default = Compare-DirectoryTree $Left $Right -Recurse -NoColor
            $compact = Compare-DirectoryTree $Left $Right -Recurse -Compact -NoColor
            $expanded = Compare-DirectoryTree $Left $Right -Recurse -ExpandMissingSubtrees -NoColor

            foreach ($label in @('LEFT files:', 'RIGHT files:', 'Same:', 'Different size:', 'LEFT only:', 'RIGHT only:', 'LEFT directories:', 'RIGHT directories:', 'LEFT-only directories:', 'RIGHT-only directories:', 'Empty-directory differences:', 'Total differences:', 'Ignored metadata differences:', 'Relevant differences:', 'Structural differences:')) {
                Get-SummaryValue $compact $label | Should -Be (Get-SummaryValue $default $label) -Because "$label must not depend on presentation mode"
                Get-SummaryValue $expanded $label | Should -Be (Get-SummaryValue $default $label) -Because "$label must not depend on presentation mode"
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

        It 'qualifies a MATCH verdict when only empty directories differ' {
            $pair = New-TestDirectoryPair
            try {
                New-Item -ItemType Directory -Path (Join-Path $pair.Left 'OnlyHere') -Force | Out-Null

                $report = Compare-DirectoryTree $pair.Left $pair.Right -Recurse -NoColor

                Get-SummaryValue $report 'Relevant differences:' | Should -Be 0
                Get-VerdictLine $report | Should -Be 'RESULT: MATCH - qualified: different empty subdirectories'
            }
            finally {
                Remove-Item -LiteralPath $pair.Base -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'qualifies a MATCH verdict when structure and ignorable metadata both differ' {
            $pair = New-TestDirectoryPair
            try {
                New-Item -ItemType Directory -Path (Join-Path $pair.Left 'OnlyHere') -Force | Out-Null
                New-TestFile (Join-Path $pair.Left 'Thumbs.db') 10

                $report = Compare-DirectoryTree $pair.Left $pair.Right -Recurse -NoColor

                Get-VerdictLine $report | Should -Be 'RESULT: MATCH - qualified: different empty subdirectories; other differences limited to ignorable metadata'
            }
            finally {
                Remove-Item -LiteralPath $pair.Base -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'describes the recursive scope and presentation mode in the header' {
            $default = Compare-DirectoryTree $Left $Right -Recurse -NoColor
            $compact = Compare-DirectoryTree $Left $Right -Recurse -Compact -NoColor
            $expanded = Compare-DirectoryTree $Left $Right -Recurse -ExpandMissingSubtrees -NoColor

            $default | Should -Contain 'Scope : Files in these directories and all subdirectories.'
            $default | Should -Contain '        Presentation: default recursive mode.'
            $compact | Should -Contain '        Presentation: compact.'
            $expanded | Should -Contain '        Presentation: expand missing subtrees.'
            $default | Should -Contain 'Match : Relative paths are compared case-insensitively.'
            $default | Should -Contain 'Same  : Matching relative path and exact size in bytes.'
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
            $different = Add-CDTColor -Line @('RESULT: DIFFERENT - 2 relevant differences | 1 ignored metadata difference')
            $match = Add-CDTColor -Line @('RESULT: MATCH - all 3 files match')

            $different | Should -Be "RESULT: $script:Escape[31mDIFFERENT$script:Escape[0m - 2 relevant differences | 1 ignored metadata difference"
            $match | Should -Be "RESULT: $script:Escape[32mMATCH$script:Escape[0m - all 3 files match"
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

                $row = $colored | Where-Object { $_ -like '*OnlyHere\*' }
                $prefix = "$script:Escape[36m<<$script:Escape[0m"
                $row.StartsWith($prefix) | Should -BeTrue
                $row.Substring($prefix.Length) | Should -Not -Match ([regex]::Escape($script:Escape))
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
            $script:Plain | Should -Contain '  <<   Exists only on LEFT'
            ($script:Plain | Where-Object { $_ -like '*Thumbs.db*' }) | Should -Match 'Ignored:'
            Get-VerdictLine $script:Plain | Should -BeLike '*DIFFERENT*'
        }
    }
}
