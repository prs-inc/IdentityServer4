param(  
    [ValidateSet('dev', 'ccnet', 'nightly', 'beta', 'rc')]
    [string]
    $BuildType = 'dev'
)

#include standard code to update dependencies in .external-bin that gets from 
# either Azure or network share
. .\Repository.Shared\dep-update.include.ps1

dotnet tool restore

# tell NuGet to use the local sources that the VS/Rider build of packages is output to
Add-NuGetPackageSource `
    -Name "Solution Packages" `
    -Path (Join-Path -Path ".build" -ChildPath "packages")
