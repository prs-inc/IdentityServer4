param(  
    [ValidateSet('dev', 'ccnet', 'nightly', 'beta', 'rc')]
    [string]
    $BuildType = 'dev'
)

dotnet tool restore

#include standard code to update dependencies in .external-bin that gets from 
# either Azure or network share
. .\Repository.Shared\dep-update.include.ps1

$nugetExe = (Download-NuGet)

Add-NuGetPackageSource -Name "Solution Packages" -Path (Join-Path -Path ".build" -ChildPath "packages")

