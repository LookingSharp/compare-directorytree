<#
.SYNOPSIS
    Placeholder Pester tests for Compare-DirectoryTree.

.DESCRIPTION
    Compare-DirectoryTree.ps1 is not yet implemented against a supplied
    specification. These tests will be replaced once
    ../../specs/Compare-DirectoryTree-Spec.md is available.
#>

BeforeAll {
    . "$PSScriptRoot/../Compare-DirectoryTree.ps1"
}

Describe 'Compare-DirectoryTree' {
    It 'is not yet implemented' {
        { Compare-DirectoryTree } | Should -Throw
    }
}
