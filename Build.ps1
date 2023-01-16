<#
.SYNOPSIS
    Builds the CodeTiger.AzureDevOps.Versioning extension.
.DESCRIPTION
    This script builds the CodeTiger.AzureDevOps.Versioning extension, and can be used to verify that changes will
    pass automated checks performed for pull requests.
#>

$ErrorActionPreference = "Stop"

Push-Location $PSScriptRoot

try {
    try {
        Push-Location $([IO.Path]::Combine($PSScriptRoot, "stamp-versions-task", "v1"))

        & npm install

        if ($LASTEXITCODE -ne 0)
        {
            throw "Running 'npm install' failed with error code $LASTEXITCODE"
        }
    
        & tsc
        
        if ($LASTEXITCODE -ne 0)
        {
            throw "Running 'tsc' failed with error code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }

    # HACK: Apparently tfx does not handle spaces in file names, and for some reason it cares about these files.
    # Since these are unnecessary, deleting them seems to be the simplest workaround.
    $filesToRemove = @(
        [IO.Path]::Combine("stamp-versions-task", "v1", "node_modules", "xpath", "docs", "function resolvers.md"),
        [IO.Path]::Combine("stamp-versions-task", "v1", "node_modules", "xpath", "docs", "namespace resolvers.md"),
        [IO.Path]::Combine("stamp-versions-task", "v1", "node_modules", "xpath", "docs", "parsed expressions.md"),
        [IO.Path]::Combine("stamp-versions-task", "v1", "node_modules", "xpath", "docs", "variable resolvers.md"),
        [IO.Path]::Combine("stamp-versions-task", "v1", "node_modules", "xpath", "docs", "xpath methods.md"))

    $filesToRemove | ForEach-Object {
        if ([IO.File]::Exists($_)) {
            Remove-Item $_
        }
    }

    & tfx extension create --manifest-globs vss-extension.json --output-path $([IO.Path]::Combine("Build", "Release"))

    if ($LASTEXITCODE -ne 0) {
        throw "Running 'tfx extension create --manifest-globs vss-extension.json' failed with error code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
