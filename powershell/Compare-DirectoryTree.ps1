<#
.SYNOPSIS
    Compares the files contained in two directories and produces a
    human-readable, self-describing report.

.DESCRIPTION
    Behavior is defined by the authoritative specification at
    ../specs/Compare-DirectoryTree-Spec.md.

    Dot-sourcing this file defines the Compare-DirectoryTree command without
    running a comparison. Running the file directly performs a comparison.

.EXAMPLE
    .\Compare-DirectoryTree.ps1 C:\Left C:\Right

.EXAMPLE
    .\Compare-DirectoryTree.ps1 C:\Left C:\Right -Recurse -Compact -NoColor
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $ReferencePath,

    [Parameter(Position = 1)]
    [string] $DifferencePath,

    [switch] $Recurse,
    [switch] $Compact,
    [switch] $ExpandMissingSubtrees,
    [switch] $ExplainMetadata,
    [switch] $NoColor
)

Set-StrictMode -Version Latest

$script:CDTMetadataCatalog = @(
    [pscustomobject]@{ Id = 'WIN-THUMBS';        Policy = 'Ignore';   Names = @('Thumbs.db');                 Patterns = @();                ShortNote = 'Windows thumbnail cache';                Explanation = 'Generated preview cache; not source content and normally regenerable.' }
    [pscustomobject]@{ Id = 'WIN-EHTHUMBS';      Policy = 'Ignore';   Names = @('ehthumbs.db');               Patterns = @();                ShortNote = 'Windows Media Center thumbnail cache';   Explanation = 'Legacy generated media-preview cache.' }
    [pscustomobject]@{ Id = 'WIN-DESKTOPINI';    Policy = 'Ignore';   Names = @('desktop.ini');               Patterns = @();                ShortNote = 'Windows folder presentation metadata';   Explanation = 'Explorer folder customization rather than substantive directory content.' }
    [pscustomobject]@{ Id = 'MAC-DSSTORE';       Policy = 'Ignore';   Names = @('.DS_Store');                 Patterns = @();                ShortNote = 'macOS Finder metadata';                  Explanation = 'Finder view/presentation metadata rather than substantive directory content.' }
    [pscustomobject]@{ Id = 'KDE-DIRECTORY';     Policy = 'Ignore';   Names = @('.directory');                Patterns = @();                ShortNote = 'KDE folder presentation metadata';       Explanation = 'Folder-specific KDE/Dolphin presentation metadata.' }
    [pscustomobject]@{ Id = 'MAC-APPLEDOUBLE';   Policy = 'Relevant'; Names = @();                            Patterns = @('._*');           ShortNote = 'AppleDouble sidecar';                    Explanation = 'May preserve resource forks, Finder information, extended attributes, or other Mac filesystem metadata.' }
    [pscustomobject]@{ Id = 'PHOTO-XMP';         Policy = 'Relevant'; Names = @();                            Patterns = @('*.xmp');         ShortNote = 'XMP photo sidecar';                      Explanation = 'May contain ratings, keywords, develop settings, edits, or intentionally maintained metadata.' }
    [pscustomobject]@{ Id = 'PHOTO-AAE';         Policy = 'Relevant'; Names = @();                            Patterns = @('*.aae');         ShortNote = 'Apple photo-edit sidecar';               Explanation = 'May represent nondestructive edits associated with a photo.' }
    [pscustomobject]@{ Id = 'PHOTO-PXD-SIDECAR'; Policy = 'Relevant'; Names = @();                            Patterns = @('*.pxd-sidecar'); ShortNote = 'Pixelmator edit sidecar';                Explanation = 'May contain layers or nondestructive editing state.' }
    [pscustomobject]@{ Id = 'PHOTO-PICASA';      Policy = 'Relevant'; Names = @('.picasa.ini', 'Picasa.ini'); Patterns = @();                ShortNote = 'Picasa photo metadata';                  Explanation = 'May contain photo-specific metadata such as face/name tagging.' }
)

function Get-CDTMetadataCatalog {
    [CmdletBinding()]
    param()

    $script:CDTMetadataCatalog
}

function Get-CDTMetadataClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $FileName
    )

    $matched = @(foreach ($rule in Get-CDTMetadataCatalog) {
        $isMatch = $false
        foreach ($name in $rule.Names) {
            if ([string]::Equals($FileName, $name, [System.StringComparison]::OrdinalIgnoreCase)) { $isMatch = $true }
        }
        foreach ($pattern in $rule.Patterns) {
            if ($FileName -like $pattern) { $isMatch = $true }
        }
        if ($isMatch) { $rule }
    })

    if ($matched.Count -eq 0) { return $null }

    # Preservation-first: a file recognized by any relevant rule stays relevant
    # even when another rule would ignore it. Resolution is deterministic.
    $relevant = @($matched | Where-Object { $_.Policy -eq 'Relevant' })
    $selected = if ($relevant.Count -gt 0) { $relevant[0] } else { $matched[0] }

    $note = if ($selected.Policy -eq 'Ignore') { "Ignored: $($selected.ShortNote)" } else { "Recognized: $($selected.ShortNote)" }

    [pscustomobject]@{
        Id          = $selected.Id
        Policy      = $selected.Policy
        ShortNote   = $selected.ShortNote
        Explanation = $selected.Explanation
        Note        = $note
    }
}

function Test-CDTIgnoredFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $FileName
    )

    $classification = Get-CDTMetadataClassification -FileName $FileName
    $null -ne $classification -and $classification.Policy -eq 'Ignore'
}

function Format-CDTByteCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [long] $Bytes
    )

    $Bytes.ToString('N0', [cultureinfo]::InvariantCulture)
}

function Format-CDTCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [long] $Count,

        [Parameter(Mandatory)]
        [string] $Singular,

        [Parameter(Mandatory)]
        [string] $Plural
    )

    '{0} {1}' -f $Count, $(if ($Count -eq 1) { $Singular } else { $Plural })
}

function New-CDTDirectoryNode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $FullName,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $RelativePath,

        [switch] $Recurse
    )

    $directory = [System.IO.DirectoryInfo]::new($FullName)

    try {
        $files = @($directory.GetFiles())
    }
    catch {
        throw "Cannot enumerate files in directory '$FullName': $($_.Exception.Message)"
    }

    $duplicateFiles = @($files | Group-Object -Property { $_.Name.ToLowerInvariant() } | Where-Object { $_.Count -gt 1 })
    if ($duplicateFiles.Count -gt 0) {
        $colliding = ($duplicateFiles[0].Group | ForEach-Object { $_.Name } | Sort-Object) -join ', '
        throw "Ambiguous case-insensitive filename collision in '$FullName': $colliding"
    }

    $node = [pscustomobject]@{
        FullName     = $FullName
        RelativePath = $RelativePath
        Files        = [ordered]@{}
        Dirs         = [ordered]@{}
    }

    foreach ($file in ($files | Sort-Object -Property Name)) {
        $node.Files[$file.Name.ToLowerInvariant()] = [pscustomobject]@{
            Name         = $file.Name
            RelativePath = if ($RelativePath) { Join-Path $RelativePath $file.Name } else { $file.Name }
            Length       = [long]$file.Length
        }
    }

    if (-not $Recurse) { return $node }

    try {
        $subdirectories = @($directory.GetDirectories())
    }
    catch {
        throw "Cannot enumerate subdirectories in directory '$FullName': $($_.Exception.Message)"
    }

    $duplicateDirs = @($subdirectories | Group-Object -Property { $_.Name.ToLowerInvariant() } | Where-Object { $_.Count -gt 1 })
    if ($duplicateDirs.Count -gt 0) {
        $colliding = ($duplicateDirs[0].Group | ForEach-Object { $_.Name } | Sort-Object) -join ', '
        throw "Ambiguous case-insensitive directory name collision in '$FullName': $colliding"
    }

    foreach ($subdirectory in ($subdirectories | Sort-Object -Property Name)) {
        $childRelative = if ($RelativePath) { Join-Path $RelativePath $subdirectory.Name } else { $subdirectory.Name }
        $node.Dirs[$subdirectory.Name.ToLowerInvariant()] = New-CDTDirectoryNode -FullName $subdirectory.FullName -RelativePath $childRelative -Recurse
    }

    $node
}

function Get-CDTSubtreeStatistic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Node
    )

    $fileCount = 0
    $dirCount = 0
    [long]$byteCount = 0
    $ignoredCount = 0

    foreach ($file in $Node.Files.Values) {
        $fileCount++
        $byteCount += $file.Length
        if (Test-CDTIgnoredFile -FileName $file.Name) { $ignoredCount++ }
    }

    foreach ($child in $Node.Dirs.Values) {
        $childStat = Get-CDTSubtreeStatistic -Node $child
        $dirCount += 1 + $childStat.DirectoryCount
        $fileCount += $childStat.FileCount
        $byteCount += $childStat.ByteCount
        $ignoredCount += $childStat.IgnoredCount
    }

    [pscustomobject]@{
        FileCount      = $fileCount
        DirectoryCount = $dirCount
        ByteCount      = $byteCount
        IgnoredCount   = $ignoredCount
    }
}

function Get-CDTSubtreeFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Node
    )

    foreach ($file in $Node.Files.Values) { $file }
    foreach ($child in $Node.Dirs.Values) { Get-CDTSubtreeFile -Node $child }
}

function Get-CDTFilelessDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Node
    )

    foreach ($child in $Node.Dirs.Values) {
        $stat = Get-CDTSubtreeStatistic -Node $child
        if ($stat.FileCount -eq 0) {
            $child
        }
        else {
            Get-CDTFilelessDirectory -Node $child
        }
    }
}

function Format-CDTDirectorySummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Statistic
    )

    $text = '{0}, {1}, {2} B' -f
        (Format-CDTCount -Count $Statistic.FileCount -Singular 'file' -Plural 'files'),
        (Format-CDTCount -Count $Statistic.DirectoryCount -Singular 'dir' -Plural 'dirs'),
        (Format-CDTByteCount -Bytes $Statistic.ByteCount)

    if ($Statistic.IgnoredCount -gt 0) {
        $text += ' | ignored metadata {0}' -f $Statistic.IgnoredCount
    }

    $text
}

function Format-CDTRelativeDirectoryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $RelativePath
    )

    if ([string]::IsNullOrEmpty($RelativePath)) { '.\' } else { "$RelativePath\" }
}

function New-CDTFileRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Class,
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $FileName,
        [AllowNull()][System.Nullable[long]] $LeftSize,
        [AllowNull()][System.Nullable[long]] $RightSize
    )

    $classification = Get-CDTMetadataClassification -FileName $FileName
    $leftText = if ($null -eq $LeftSize) { '<missing>' } else { Format-CDTByteCount -Bytes $LeftSize }
    $rightText = if ($null -eq $RightSize) { '<missing>' } else { Format-CDTByteCount -Bytes $RightSize }
    $note = if ($classification) { $classification.Note } else { '' }

    [pscustomobject]@{
        Class   = $Class
        SortKey = $Path
        IsDir   = $false
        Path    = $Path
        Left    = $leftText
        Right   = $rightText
        Note    = $note
        Meta    = $classification
        Text    = ''
    }
}

function New-CDTDirectoryRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Class,
        [Parameter(Mandatory)][string] $DisplayPath,
        [Parameter(Mandatory)][string] $Summary
    )

    [pscustomobject]@{
        Class   = $Class
        SortKey = $DisplayPath
        IsDir   = $true
        Path    = $DisplayPath
        Left    = ''
        Right   = ''
        Note    = ''
        Meta    = $null
        Text    = '[DIR] {0}   {1}' -f $DisplayPath, $Summary
    }
}

function Add-CDTOneSidedSubtree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject] $Node,
        [Parameter(Mandatory)][string] $Class,
        [Parameter(Mandatory)][psobject] $Context
    )

    $stat = Get-CDTSubtreeStatistic -Node $Node
    $directoriesRepresented = 1 + $stat.DirectoryCount

    if ($Class -eq '<<') {
        $Context.Stat.LeftOnly += $stat.FileCount
        $Context.Stat.LeftOnlyDirectories += $directoriesRepresented
    }
    else {
        $Context.Stat.RightOnly += $stat.FileCount
        $Context.Stat.RightOnlyDirectories += $directoriesRepresented
    }

    $Context.Stat.Ignored += $stat.IgnoredCount

    if ($stat.FileCount -eq 0) {
        $Context.Stat.EmptyDirectoryDifferences += $directoriesRepresented
    }

    foreach ($file in (Get-CDTSubtreeFile -Node $Node)) {
        $classification = Get-CDTMetadataClassification -FileName $file.Name
        if ($classification) { $Context.EncounteredMetadata[$classification.Id] = $classification }
    }

    if ($Context.Mode -ne 'Expand' -or $stat.FileCount -eq 0) {
        $Context.Rows.Add((New-CDTDirectoryRow -Class $Class -DisplayPath (Format-CDTRelativeDirectoryPath -RelativePath $Node.RelativePath) -Summary (Format-CDTDirectorySummary -Statistic $stat))) | Out-Null
        return
    }

    foreach ($file in (Get-CDTSubtreeFile -Node $Node | Sort-Object -Property RelativePath)) {
        $left = if ($Class -eq '<<') { $file.Length } else { $null }
        $right = if ($Class -eq '>>') { $file.Length } else { $null }
        $Context.Rows.Add((New-CDTFileRow -Class $Class -Path $file.RelativePath -FileName $file.Name -LeftSize $left -RightSize $right)) | Out-Null
    }

    foreach ($filelessDirectory in (Get-CDTFilelessDirectory -Node $Node)) {
        $filelessStat = Get-CDTSubtreeStatistic -Node $filelessDirectory
        $Context.Rows.Add((New-CDTDirectoryRow -Class $Class -DisplayPath (Format-CDTRelativeDirectoryPath -RelativePath $filelessDirectory.RelativePath) -Summary (Format-CDTDirectorySummary -Statistic $filelessStat))) | Out-Null
    }
}

function Add-CDTDirectoryPair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject] $Left,
        [Parameter(Mandatory)][psobject] $Right,
        [Parameter(Mandatory)][psobject] $Context
    )

    $directSame = 0
    $directLeftOnly = 0
    $directRightOnly = 0
    $directDifferent = 0
    $directIgnored = 0
    $directRows = [System.Collections.Generic.List[psobject]]::new()

    $keys = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $Left.Files.Keys) { $keys.Add($key) }
    foreach ($key in $Right.Files.Keys) { if (-not $Left.Files.Contains($key)) { $keys.Add($key) } }

    foreach ($key in $keys) {
        $leftFile = if ($Left.Files.Contains($key)) { $Left.Files[$key] } else { $null }
        $rightFile = if ($Right.Files.Contains($key)) { $Right.Files[$key] } else { $null }

        $name = if ($leftFile) { $leftFile.Name } else { $rightFile.Name }
        $path = if ($leftFile) { $leftFile.RelativePath } else { $rightFile.RelativePath }

        $classification = Get-CDTMetadataClassification -FileName $name
        $isIgnored = $null -ne $classification -and $classification.Policy -eq 'Ignore'

        if ($leftFile -and $rightFile) {
            if ($leftFile.Length -eq $rightFile.Length) {
                $Context.Stat.Same++
                $directSame++
                continue
            }

            $Context.Stat.DifferentSize++
            $directDifferent++
            $class = '<>'
            $row = New-CDTFileRow -Class $class -Path $path -FileName $name -LeftSize $leftFile.Length -RightSize $rightFile.Length
        }
        elseif ($leftFile) {
            $Context.Stat.LeftOnly++
            $directLeftOnly++
            $class = '<<'
            $row = New-CDTFileRow -Class $class -Path $path -FileName $name -LeftSize $leftFile.Length -RightSize $null
        }
        else {
            $Context.Stat.RightOnly++
            $directRightOnly++
            $class = '>>'
            $row = New-CDTFileRow -Class $class -Path $path -FileName $name -LeftSize $null -RightSize $rightFile.Length
        }

        if ($isIgnored) {
            $Context.Stat.Ignored++
            $directIgnored++
        }

        if ($classification) { $Context.EncounteredMetadata[$classification.Id] = $classification }

        $directRows.Add($row) | Out-Null
    }

    if ($Context.Mode -eq 'Compact') {
        if ($directRows.Count -gt 0) {
            $summary = '{0} same | << {1} | >> {2} | <> {3}' -f $directSame, $directLeftOnly, $directRightOnly, $directDifferent
            if ($directIgnored -gt 0) { $summary += ' | ignored {0}' -f $directIgnored }
            $Context.Rows.Add((New-CDTDirectoryRow -Class '<>' -DisplayPath (Format-CDTRelativeDirectoryPath -RelativePath $Left.RelativePath) -Summary $summary)) | Out-Null
        }
    }
    else {
        foreach ($row in $directRows) { $Context.Rows.Add($row) | Out-Null }
    }

    if (-not $Context.Recurse) { return }

    $dirKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $Left.Dirs.Keys) { $dirKeys.Add($key) }
    foreach ($key in $Right.Dirs.Keys) { if (-not $Left.Dirs.Contains($key)) { $dirKeys.Add($key) } }

    foreach ($key in ($dirKeys | Sort-Object)) {
        $leftDir = if ($Left.Dirs.Contains($key)) { $Left.Dirs[$key] } else { $null }
        $rightDir = if ($Right.Dirs.Contains($key)) { $Right.Dirs[$key] } else { $null }

        if ($leftDir -and $rightDir) {
            Add-CDTDirectoryPair -Left $leftDir -Right $rightDir -Context $Context
        }
        elseif ($leftDir) {
            Add-CDTOneSidedSubtree -Node $leftDir -Class '<<' -Context $Context
        }
        else {
            Add-CDTOneSidedSubtree -Node $rightDir -Class '>>' -Context $Context
        }
    }
}

function Format-CDTSummaryLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Label,
        [Parameter(Mandatory)][string] $Value
    )

    $width = 33
    $padding = $width - $Label.Length - $Value.Length
    if ($padding -lt 1) { $padding = 1 }
    '{0}{1}{2}' -f $Label, (' ' * $padding), $Value
}

function Format-CDTDifferenceRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject] $Row,
        [Parameter(Mandatory)][int] $PathWidth,
        [Parameter(Mandatory)][int] $LeftWidth,
        [Parameter(Mandatory)][int] $RightWidth
    )

    if ($Row.IsDir) {
        return ('{0}  {1}' -f $Row.Class, $Row.Text).TrimEnd()
    }

    ('{0}  {1}{2}   {3}   {4}' -f
        $Row.Class,
        $Row.Path.PadRight($PathWidth),
        $Row.Left.PadLeft($LeftWidth),
        $Row.Right.PadLeft($RightWidth),
        $Row.Note).TrimEnd()
}

function Get-CDTVerdictLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject] $Stat
    )

    $relevant = $Stat.TotalDifferences - $Stat.Ignored

    if ($relevant -gt 0) {
        $parts = @(Format-CDTCount -Count $relevant -Singular 'relevant difference' -Plural 'relevant differences')
        if ($Stat.EmptyDirectoryDifferences -gt 0) {
            $parts += Format-CDTCount -Count $Stat.EmptyDirectoryDifferences -Singular 'empty-subdirectory difference' -Plural 'empty-subdirectory differences'
        }
        if ($Stat.Ignored -gt 0) {
            $parts += Format-CDTCount -Count $Stat.Ignored -Singular 'ignored metadata difference' -Plural 'ignored metadata differences'
        }
        return 'RESULT: NOT THE SAME - {0}' -f ($parts -join ' | ')
    }

    $structureDiffers = $Stat.EmptyDirectoryDifferences -gt 0
    $metadataDiffers = $Stat.Ignored -gt 0

    if ($structureDiffers -and $metadataDiffers) {
        return 'RESULT: SAME - qualified: different empty subdirectories; other differences limited to ignorable metadata'
    }
    if ($structureDiffers) {
        return 'RESULT: SAME - qualified: different empty subdirectories'
    }
    if ($metadataDiffers) {
        return 'RESULT: SAME - qualified: differences limited to {0}' -f (Format-CDTCount -Count $Stat.Ignored -Singular 'ignored metadata file' -Plural 'ignored metadata files')
    }

    'RESULT: SAME - all {0} match' -f (Format-CDTCount -Count $Stat.Same -Singular 'file' -Plural 'files')
}

function Add-CDTColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Line
    )

    $esc = [char]27
    $reset = "$esc[0m"
    $markerColor = @{ '<<' = "$esc[36m"; '>>' = "$esc[35m"; '<>' = "$esc[33m" }

    foreach ($text in $Line) {
        $colored = $text

        if ($text.Length -ge 2 -and $markerColor.ContainsKey($text.Substring(0, 2))) {
            $marker = $text.Substring(0, 2)
            $colored = '{0}{1}{2}{3}' -f $markerColor[$marker], $marker, $reset, $text.Substring(2)
        }

        $ignoredIndex = $colored.IndexOf('Ignored: ')
        if ($ignoredIndex -ge 0) {
            $colored = '{0}{1}{2}{3}' -f $colored.Substring(0, $ignoredIndex), "$esc[2m", $colored.Substring($ignoredIndex), $reset
        }

        if ($text.StartsWith('RESULT: NOT THE SAME')) {
            $colored = $colored.Replace('NOT THE SAME', "$esc[31mNOT THE SAME$reset")
        }
        elseif ($text.StartsWith('RESULT: SAME')) {
            $colored = $colored -replace '^RESULT: SAME', "RESULT: $esc[32mSAME$reset"
        }

        $colored
    }
}

function Test-CDTColorSupported {
    [CmdletBinding()]
    param()

    if ([System.Console]::IsOutputRedirected) { return $false }
    if ($env:NO_COLOR) { return $false }

    try {
        return $null -ne $Host -and $Host.UI.SupportsVirtualTerminal
    }
    catch {
        return $false
    }
}

function Compare-DirectoryTree {
    <#
    .SYNOPSIS
        Compares the files contained in two directories and produces a
        human-readable, self-describing report.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $ReferencePath,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $DifferencePath,

        [switch] $Recurse,
        [switch] $Compact,
        [switch] $ExpandMissingSubtrees,
        [switch] $ExplainMetadata,
        [switch] $NoColor
    )

    if ($Compact -and $ExpandMissingSubtrees) {
        throw '-Compact and -ExpandMissingSubtrees cannot be combined.'
    }
    if ($Compact -and -not $Recurse) {
        throw '-Compact requires -Recurse.'
    }
    if ($ExpandMissingSubtrees -and -not $Recurse) {
        throw '-ExpandMissingSubtrees requires -Recurse.'
    }

    $roots = foreach ($candidate in @($ReferencePath, $DifferencePath)) {
        if (-not (Test-Path -LiteralPath $candidate)) {
            throw "Path not found: $candidate"
        }
        $item = Get-Item -LiteralPath $candidate -Force
        if ($item -isnot [System.IO.DirectoryInfo]) {
            throw "Path is not a directory: $candidate"
        }
        $item.FullName
    }

    $leftRoot = $roots[0]
    $rightRoot = $roots[1]

    $leftTree = New-CDTDirectoryNode -FullName $leftRoot -RelativePath '' -Recurse:$Recurse
    $rightTree = New-CDTDirectoryNode -FullName $rightRoot -RelativePath '' -Recurse:$Recurse

    $mode = if ($Compact) { 'Compact' } elseif ($ExpandMissingSubtrees) { 'Expand' } else { 'Default' }

    $stat = [pscustomobject]@{
        LeftFiles                 = 0
        RightFiles                = 0
        Same                      = 0
        DifferentSize             = 0
        LeftOnly                  = 0
        RightOnly                 = 0
        Ignored                   = 0
        LeftOnlyDirectories       = 0
        RightOnlyDirectories      = 0
        EmptyDirectoryDifferences = 0
        TotalDifferences          = 0
    }

    $context = [pscustomobject]@{
        Rows                = [System.Collections.Generic.List[psobject]]::new()
        Stat                = $stat
        Mode                = $mode
        Recurse             = [bool]$Recurse
        EncounteredMetadata = [ordered]@{}
    }

    Add-CDTDirectoryPair -Left $leftTree -Right $rightTree -Context $context

    $leftStat = Get-CDTSubtreeStatistic -Node $leftTree
    $rightStat = Get-CDTSubtreeStatistic -Node $rightTree
    $stat.LeftFiles = $leftStat.FileCount
    $stat.RightFiles = $rightStat.FileCount
    $stat.TotalDifferences = $stat.DifferentSize + $stat.LeftOnly + $stat.RightOnly
    $relevant = $stat.TotalDifferences - $stat.Ignored

    $rows = @(
        foreach ($class in @('<<', '>>', '<>')) {
            , @($context.Rows | Where-Object { $_.Class -eq $class } | Sort-Object -Property @{ Expression = { $_.SortKey.ToLowerInvariant() } })
        }
    )

    $fileRows = @($context.Rows | Where-Object { -not $_.IsDir })
    $pathWidth = 38
    $leftWidth = 17
    $rightWidth = 18
    foreach ($row in $fileRows) {
        if (($row.Path.Length + 2) -gt $pathWidth) { $pathWidth = $row.Path.Length + 2 }
        if ($row.Left.Length -gt $leftWidth) { $leftWidth = $row.Left.Length }
        if ($row.Right.Length -gt $rightWidth) { $rightWidth = $row.Right.Length }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $add = { param([string] $Text) $lines.Add($Text) | Out-Null }

    & $add 'FILE COMPARISON'
    & $add '==============='
    & $add ''
    & $add "LEFT : $leftRoot"
    & $add "RIGHT: $rightRoot"
    & $add ''

    if ($Recurse) {
        $modeText = switch ($mode) {
            'Compact' { 'compact directory summaries' }
            'Expand'  { 'one-sided subtrees expanded file by file' }
            default   { 'one-sided subtrees collapsed at the highest missing directory' }
        }
        & $add 'Scope : All files beneath these directories; subdirectories ARE searched.'
        & $add '        Hidden and system files ARE included.'
        & $add "        Presentation: $modeText."
        & $add 'Match : Root-relative paths are compared case-insensitively.'
        & $add 'Same  : Matching root-relative path and exact size in bytes.'
    }
    else {
        & $add 'Scope : Files in these directories only; subdirectories are NOT searched.'
        & $add '        Hidden and system files ARE included.'
        & $add 'Match : Filenames are compared case-insensitively.'
        & $add 'Same  : Matching filename and exact size in bytes.'
    }

    & $add 'Ignore: Known disposable metadata/cache files are reported but do not'
    & $add '        affect the final comparison result.'
    & $add 'Note  : Contents, hashes, timestamps, attributes, and other metadata are'
    & $add '        NOT compared.'
    & $add ''
    & $add 'SUMMARY'
    & $add '-------'
    & $add (Format-CDTSummaryLine -Label 'LEFT files:' -Value $stat.LeftFiles)
    & $add (Format-CDTSummaryLine -Label 'RIGHT files:' -Value $stat.RightFiles)
    & $add (Format-CDTSummaryLine -Label 'Same:' -Value $stat.Same)
    & $add (Format-CDTSummaryLine -Label 'Different size:' -Value $stat.DifferentSize)
    & $add (Format-CDTSummaryLine -Label 'LEFT only:' -Value $stat.LeftOnly)
    & $add (Format-CDTSummaryLine -Label 'RIGHT only:' -Value $stat.RightOnly)

    if ($Recurse) {
        & $add ''
        & $add (Format-CDTSummaryLine -Label 'LEFT-only directories:' -Value $stat.LeftOnlyDirectories)
        & $add (Format-CDTSummaryLine -Label 'RIGHT-only directories:' -Value $stat.RightOnlyDirectories)
        & $add (Format-CDTSummaryLine -Label 'Empty-subdirectory differences:' -Value $stat.EmptyDirectoryDifferences)
    }

    & $add ''
    & $add (Format-CDTSummaryLine -Label 'Total differences:' -Value $stat.TotalDifferences)
    & $add (Format-CDTSummaryLine -Label 'Ignored metadata differences:' -Value $stat.Ignored)
    & $add (Format-CDTSummaryLine -Label 'Relevant differences:' -Value $relevant)

    if ($context.Rows.Count -gt 0) {
        & $add ''
        & $add 'DIFFERENCES'
        & $add '-----------'
        & $add ''
        & $add ('    {0}{1}   {2}   {3}' -f
            'File'.PadRight($pathWidth),
            'LEFT size (bytes)'.PadLeft($leftWidth),
            'RIGHT size (bytes)'.PadLeft($rightWidth),
            'Note')
        & $add ('    {0}{1}   {2}   {3}' -f
            ('-' * 4).PadRight($pathWidth),
            ('-' * 17).PadLeft($leftWidth),
            ('-' * 18).PadLeft($rightWidth),
            '----')

        $emitted = $false
        foreach ($classRows in $rows) {
            if ($classRows.Count -eq 0) { continue }
            if ($emitted) { & $add '' }
            foreach ($row in $classRows) {
                & $add (Format-CDTDifferenceRow -Row $row -PathWidth $pathWidth -LeftWidth $leftWidth -RightWidth $rightWidth)
            }
            $emitted = $true
        }

        & $add ''
        & $add 'Legend:'
        & $add '  <<  Exists only on LEFT'
        & $add '  >>  Exists only on RIGHT'
        if ($Recurse) {
            & $add '  <>  Same relative path, different size'
        }
        else {
            & $add '  <>  Same filename, different size'
        }
    }

    & $add ''
    & $add (Get-CDTVerdictLine -Stat $stat)

    if ($ExplainMetadata -and $context.EncounteredMetadata.Count -gt 0) {
        & $add ''
        & $add 'METADATA EXPLANATIONS'
        & $add '---------------------'
        foreach ($id in $context.EncounteredMetadata.Keys) {
            $metadata = $context.EncounteredMetadata[$id]
            & $add ('  {0}  {1} - {2}' -f $id, $metadata.Note, $metadata.Explanation)
        }
    }

    $output = $lines.ToArray()

    if (-not $NoColor -and (Test-CDTColorSupported)) {
        return Add-CDTColor -Line $output
    }

    $output
}

if ($MyInvocation.InvocationName -ne '.') {
    Compare-DirectoryTree @PSBoundParameters
}
