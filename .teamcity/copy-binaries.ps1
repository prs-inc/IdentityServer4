<#
.SYNOPSIS
Copies the IdentityServer4 packages directory for the Branch and BuildType under 
the IdentityServer working directory out to the software-library on Azure 
Blob Container.  There is no content moved to QA Downloads because this is purely
a library and there are no deployments.

.PARAMETER Branch
The name of the branch that is being cleaned up

.PARAMETER BuildType
The type of build performed - either 'ccnet' or 'rc'

.PARAMETER CheckoutPath
The path to the directory that the TeamCity Agent used as the working directory
for the code checked out from the repository.

#>

param (
    [string]$Branch,
    [string]$BuildType,
    [string]$CheckoutPath = ''
)

# dotsource common functions
. .\.include.ps1
. .\copy-binaries.include.ps1

# The .build directory at the root of the working directory is the location where build output that should
# be considered the build artifacts is at.
$buildPath = [System.IO.Path]::Combine($CheckoutPath, '.build')

# This is the location the csproj files are configured to output the NuGet packages to.
$packagesPath = [System.IO.Path]::Combine($buildPath, 'packages')

# Read the version.xml to figure out what the name of the Release is.  Not using the branch name because story/bug
# branches will be created that are not version numbers.  But this should not really matter because right now this
# script is only called for RC builds and those should only be done on branches with a valid release version.
$doc = [xml](Get-Content -Path ([System.IO.Path]::Combine($buildPath, 'artifacts', 'version.xml')))
$productVersion = [System.Version]::Parse($doc.version.product.version)

# Use the main IdentityServer4 nupkg file to figure out what the package version is so we can use that in the zip
# file name.  We are not using just the $BranchName (typically the Release version) because each RC build in that
# branch will generate a unique package version (see the IdentityServer4/Repository.Shared/root.build.ps1 file for
# the exact code to set $PackageVersion) each time a build is completed.  For example, the 5th RC build in 6.1.2 would
# create a package version of 6.1.2005. Any ccnet build done after the 5th RC build would be considered an alpha build
# in preperation for the 6th RC build that has not been done yet so it would create a package version of 
# 6.1.2006-alpha.{time}
$f = @(Get-ChildItem -Path ([System.IO.Path]::Combine($packagesPath , "IdentityServer4.$($productVersion.ToString(2)).*.nupkg")) |
        Sort-Object -Property 'LastWriteTime' -Descending)[0]
$zipFileName = $f.Name.Replace('Server4.', 'Server4-').Replace('.nupkg', '.zip')

$zipPath = [System.IO.Path]::Combine($buildPath, $zipFilename)

Compress-Archive `
    -Path ([System.IO.Path]::Combine($packagesPath, '*')) `
    -Destination $zipPath `
    -Force

# copy IdentityServer4 packages to software library on Azure.  Don't want to use the Copy-BinariesToSoftwareLibrary
# because of the logic it contains for RC builds.  We always want the packages to 
Copy-BinariesToAzureSoftwareLibrary `
    -SourceFile $zipPath `
    -BuildType $BuildType

# not adding the IdentityServer4 binaries to symbol store because the dll/pdb is contained in the NuGet Package