<#
.SYNOPSIS
Organizes the ArtifactsPath to have a 'binaries' and 'installers' folder

.PARAMETER ArtifactsPath
The path to the local artifacts that have been collected
for the build

.PARAMETER BuildType
The type of build to perform - either 'dev', 'ccnet', 'beta', or 'rc'

#>

param(
  [string]$ArtifactsPath = '.\.build\artifacts',
  [string]$BuildType = 'dev'
)

function New-Directory($Path){
    if (!(Test-Path -Path $Path)) {
        New-Item -Path $Path -ItemType 'Directory'
    }
}

# this directory structure needs to be synced with what is in buildserver-utils/dev/IdentityServer4/copy-binaries.ps1

New-Directory "$ArtifactsPath\packages"

# take the NuGet packages the sln and csproj have output and move it to a packages folder
# so that other solutions can download this version and update the packages
Copy-Item -Path ".\.build\packages\*" `
    -Destination "$ArtifactsPath\packages\" `
    -Force

Move-Item -Path "$ArtifactsPath\version.xml" `
    -Destination "$ArtifactsPath\packages\version.xml" `
    -Force

# delete the directories that are not binaries|installers|packages - those 3 directories will be used
# by the post build packaging code
Get-ChildItem -Path "$ArtifactsPath\*" -Directory -Exclude 'binaries', 'installers', 'packages' | Remove-Item
