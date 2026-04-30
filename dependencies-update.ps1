param(  
    [ValidateSet('dev', 'ccnet', 'nightly', 'beta', 'rc')]
    [string]
    $BuildType = 'dev'
)

# include standard code to update dependencies in .external-bin that gets from 
# either Azure or network share
. ([System.IO.Path]::Combine($rootPath, 'Repository.Shared', 'dep-update.include.ps1'))

# tell NuGet to use the local sources that the VS/Rider build of packages is output to
Add-NuGetPackageSource `
    -Name "Solution Packages" `
    -Path (Join-Path -Path ".build" -ChildPath "packages")

if (Test-Path -Path 'dotnet-tools.json') {
    dotnet tool restore
}