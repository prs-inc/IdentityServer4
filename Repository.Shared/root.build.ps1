param(
    [string]
    $ProductName = '',
    
    [String[]]
    $Solutions,

    [ValidateSet('dev', 'ccnet', 'nightly', 'beta', 'rc')]
    [string]
    $BuildType = 'dev'
)

. .\filesystem.include.ps1

# change the git.exe output it sends to STDERR to go to STDOUT so that the 
# progress reports or additional info that git.exe writes to STDERR are not
# considered an error by cc.net
$env:GIT_REDIRECT_STDERR = '2>&1'

# this build file will be executed in the directory of Repository.Shared so that
# will be the starting point for all file ops.  Need to get the root because many
# of the files/directories are based off root path
$root = (Resolve-Path '..')

$rootArtifactsPath = Join-Path -Path $root -ChildPath "\.build\artifacts"

#read from company.xml
$CompanyName = 'CaseMaxSolutions'

#read in version.xml
$vcsRevision = ''
$vcsBranch = ''

$now = (Get-Date)
$copyright = "Copyright 1999-$($now.Year) © CaseMaxSolutions"
$knownas = ''

# this is storing the Nth build of the Product that is being performed.
$buildNumber = 0

# CaseMax Release = Major.Minor.Point
# Version = Major.Minor.Build.Revision in standard MS talk.
#
# ProductVersion is how the application is known by the TP Release - so this
# will be something like 19.2 and 20.1.  This can include what is called a
# point release by the planning team such as 19.2.1, 19.2.2, and 19.2.3.  If
# this is not a point release then it will be 19.2.0 and 20.1.0 even though
# everyone refers to it as 19.2 and 20.1
[System.Version]$ProductVersion = [System.Version]::Parse('0.0.0')

# Will contain the incremented build number.  The Revision 
# property will be the total number of hours since the last RC build. 
# FileInfoVersion is 4 parts used by MSI to determine if the binary file in the MSI is newer
# that was is on disk. We keep it close to ProductVersion for communication except for that
# the Build and Revision part will be different.  
# The Build will be 4 digits - (ReleasePoint * 1000) + FileRevision.  
# The Revision will be based on number of hours since last RC build.
[System.Version]$FileInfoVersion = [System.Version]::Parse('0.0.0.0')

# InstallerVersion is 3 parts used by MSI to determine if an upgrade can be 
# performed. We keep it close to ProductVersion for communication except for that
# the Build part will be 4 digits - (PointBuild * 1000) + FileRevision. The Revision
# will be 0 because it is insignificant to MSI
[System.Version]$InstallerVersion = [System.Version]::Parse('0.0.0')

# AssemblyVersion is used by the .NET CLR determines compatibility matches.
# This will be the same value as ProductVersion because we intend to follow 
# semver with API compatibility
[System.Version]$AssemblyVersion = [System.Version]::Parse('0.0.0.0')

# PackageVersion is going to be the same as InstallerVersion except it will
# include "-alpha" for non RC builds.
# PackageVersion is used by NuGet and is supposed to follow Semantic Versioning.  
# We still have to work with Visual Studio/MSBuild/NuGet.  Since the Build for the 
# PackageVersion will be increased with each rc build that should allow for the 
# Build Server to have a new unique Major.Minor.Build.  On Debug builds the pre-release info is
# going to be auto-set based on //file[date] and that will be set in the 
# Directory.Build.props file.  This allows for the developer to always have 
# new package version with each build.
$PackageVersion = '0.0.0-alpha.0'

Add-BuildTask -Name Init -Jobs {
    _Get-VCSInfo
    Write-Host "building rev $vcsRevision on branch $vcsBranch for company $CompanyName"

    _Get-VersionFromXml
}

Add-BuildTask -Name DependenciesUpdate -Jobs {

    #dependencies-update.ps1 needs to be executed from correct working directory
    Set-Location $root
    
    .\dependencies-update.ps1 -BuildType $BuildType

    Set-Location $BuildRoot
}

Add-BuildTask -Name Build-All -Jobs DependenciesUpdate, Init, Clean, UpdateAssemblyInfo, {

    foreach ($_ in $Solutions){
        $targets = @('Build', 'Setup', 'Package')
        Invoke-SlnBuild -Solution $_ -Target $targets
    }

    # now that we know code base is good we can run the tests unless we are
    # doing an rc or beta build
    if ($BuildType -notin @('beta', 'rc')){
        foreach ($_ in $Solutions){
            Invoke-SlnBuild -Solution $_ -Target 'Test'
        }
    }

    # The version.xml gets copied as part of Move-SolutionArtifacts so have to make
    # sure it is updated if it needs to be.  Only need to write changes to version.xml
    # when we are doing an rc build.  The other types of build just generate alpha builds
    # for next build.
    if ((Test-Path -Path "$root\version.xml") -and ($BuildType -eq 'rc')){
        Set-VersionFromXml
    }

    # Move all of the solution level artifacts up to the root level artifacts.
    # Using move instead of copy because I don't need duplicate files and the
    # build is all complete.  So there is no point to keeping those files in
    # their original directory.
    Move-SolutionArtifacts
    
    if ($BuildType -ne 'dev'){

        # this file should only exist for CaseMax root.  There is some special organizing of
        # the root artifacts path
        if (Test-Path -Path "$root\build-all-organize.ps1"){
            Set-Location $root
            .\build-all-organize.ps1 -ArtifactsPath $rootArtifactsPath -BuildType $BuildType
            Set-Location $BuildRoot
        }

        Move-ToReleaseFolder
        
        if ($BuildType -eq 'rc'){
            Commit-VCS 
        }

    }

}

Add-BuildTask -Name UpdateAssemblyInfo -Jobs Init, {
    Write-CommonAssemblyInfo
}

Add-BuildTask -Name Build-Package -Jobs DependenciesUpdate, Init, Clean, UpdateAssemblyInfo, Setup-IIS, Setup-Workpoint, {
    foreach ($_ in $Solutions){
        Invoke-SlnBuild -Solution $_ -Target 'Build', 'Setup', 'Package'
    }
}

Add-BuildTask -Name Clean -Jobs Init, {
    # perform the root level cleanup before asking each solution to clean up
    # the files the solution creates
    New-Directory -Path $rootArtifactsPath
    
    #need to wipe out the NuGet build output to get clean package restore
    if ($Solutions.Count -gt 1) {
        New-Directory -Path (Combine-Paths -Paths $root, '.build', 'packages')
    }

    # For our local NuGet Packages we want to get rid of any that have been put into the Package Cache
    # because our builds will not increment the Package Version.  So what could happen is that we could
    # build Solution PRS.Aspose and create an updated nupkg for Package Version, then go to build Solution 
    # PRS.CMS but NuGet would see that it already had Package Version of PRS.Aspose nupkg so it would not 
    # use the latest nupkg file because the Package Version has not changed. So we are removing any PRS.*
    # nupkg's from the cache.
    foreach ($_ in $Solutions) {
        Invoke-SlnBuild -Solution $_ -Target 'Clean'
        Delete-NuGetGlobalPackages -Solution $_ -VersionPrefix $AssemblyVersion.Major
    }
}

Add-BuildTask -Name Build -Jobs Init, UpdateAssemblyInfo, {
    foreach ($_ in $Solutions) {
        Invoke-SlnBuild -Solution $_ -Target 'Build'
    }
}

Add-BuildTask -Name Setup -Jobs Init, {
    foreach ($_ in $Solutions) {
        Invoke-SlnBuild -Solution $_ -Target 'Setup'
    }
}

Add-BuildTask -Name Test -Jobs Init, Build, Setup, {
    foreach ($_ in $Solutions) {
        Invoke-SlnBuild -Solution $_ -Target 'Test'
    }
}

Add-BuildTask -Name Package -Jobs Init, Build, {
    foreach ($_ in $Solutions) {
        Invoke-SlnBuild -Solution $_ -Target 'Package'
    }
}

# vcs-info.include.build
function _Get-VCSInfo {
    $script:vcsRevision = $(git log -1 --pretty="%H")

    $logDate = $(git log -1 --pretty="%cd" --date iso)
    $script:vcsDate = [DateTime]::Parse($logDate)
    
    $script:vcsBranch = $(git symbolic-ref --short HEAD)
}

function _Get-VersionFromXml {
    
    # before I can get the version I need to make sure that the dependencies have been copied down
    # if there is no version.xml file at the root and there is no version in the external-bin/CMS 
    # directory.  If the root one doesn't exist that means we are in a Firm specific build so we 
    # need to check to see if the external-bin has been populated.  On build servers, the external-bin
    # directory is always clean so we know we need to do update dependencies
    if (!(Test-Path -Path "$root\version.xml")){
        Write-Error "unable to get version.xml file at the root"
    }

    $path = (Resolve-Path -Path "$root\version.xml")
    $xml = [xml](Get-Content -Path $path)

    $Script:knownas = $xml.version.product.knownas
    $fileDate = [DateTime]::Parse($xml.version.file.date)

    # This alpha build number needs to be set to allow for a developer to generate new nupkg versions
    # Using TotalMinutes because developers can do builds fairly quickly and this is not part of the 
    # official "Version" - just info about the alpha build in the SemVer of nupkg file.
    $alphaBuildNum = [Math]::Ceiling($now.Subtract($fileDate).TotalMinutes)

    # this is a Major.Minor.Build - or (2 digit Year).(ReleaseInYear).(PointInRelease)
    $Script:ProductVersion = [System.Version]::Parse($xml.version.product.version)

    # Have to increment the Revision on a file because that is how MSI knows that file is newer.  Using TotalHours
    # because ccnet or dev builds that might be moved out to other machines for testing don't happen that often.
    # This should allow for about 7 years between current build and last rc build.  Even when doing an RC build
    # this needs to be compared to last RC build because all the alpha builds between previous RC and the RC being
    # performed now could be out there.  So this File needs to be considered newer than an alpha build.
    $fileRevision = [Math]::Ceiling($now.Subtract($fileDate).TotalHours)
    
    # when we are in CaseMax we are building the "next" revision of the Version of code now,
    $Script:buildNumber = [int]$xml.version.file.revision + 1

    $major = $Script:ProductVersion.Major
    $minor = $Script:ProductVersion.Minor
    $point = $Script:ProductVersion.Build
    
    # MSI Product Version can only consist of 3 parts so need to combine the point release
    $installerBuild = ($point * 1000) + $Script:buildNumber
    $Script:InstallerVersion = New-Object System.Version($major, $minor, $installerBuild)

    $Script:FileInfoVersion = New-Object System.Version($major, $minor, $installerBuild, $fileRevision)
    
    $Script:AssemblyVersion = New-Object System.Version($major, $minor, $installerBuild)

    # The PackageVersion only uses the major.minor.build of the AssemblyVersion since it is using
    # semver.  If this is not an rc build then we will add pre-release identifier to indicate the
    # nupkg is an alpha build
    $Script:PackageVersion = $Script:AssemblyVersion.ToString(3)
    if ($BuildType -ne 'rc'){
        $Script:PackageVersion = "$($Script:PackageVersion)-alpha.$alphaBuildNum"
    }
    
    Write-Host "building versions"
    Write-Host "Product   : $ProductVersion"
    Write-Host "File      : $FileInfoVersion"
    Write-Host "Installer : $InstallerVersion"
    Write-Host "Assembly  : $AssemblyVersion"
    Write-Host "Package   : $PackageVersion"
}

function Write-CommonAssemblyInfo {
    $solutionVersion = $PackageVersion
    if ($PackageVersion.Contains('-alpha')){
        $solutionVersion = $PackageVersion.Substring(0, $PackageVersion.IndexOf('-alpha')) + "-alpha*"
    }

    if (Test-Path -Path "$root\Directory.Build.props") {
        Write-Host "Updating Directory.Build.props file"
        # need to use Resolve-Path because the working directory used by Xml.Save is
        # different than the current powershell directory
        $path = (Resolve-Path -Path "$root\Directory.Build.props")
        
        $doc = [xml](Get-Content -Path $path)

        $doc.SelectSingleNode('//AssemblyVersion').InnerText = $AssemblyVersion
        $doc.SelectSingleNode('//Company').InnerText = $CompanyName
        $doc.SelectSingleNode('//Copyright').InnerText = "$copyright"
        $doc.SelectSingleNode('//FileVersion').InnerText = "$FileInfoVersion"
        $doc.SelectSingleNode('//InformationalVersion').InnerText = "$PackageVersion"
        $doc.SelectSingleNode('//Product').InnerText = "$knownas $ProductVersion"
        $doc.SelectSingleNode('//PackageVersion').InnerText = "$PackageVersion"
        $doc.SelectSingleNode('//SolutionVersion').InnerText = $solutionVersion

        $doc.Save($path)
    }
}

# version-increment.build
function Set-VersionFromXml {
    # need to use Resolve-Path because the working directory used by Xml.Save is
    # different than the current powershell directory
    $path = (Resolve-Path -Path "$root\version.xml")

    $xml = [xml](Get-Content -Path $path)
    
    # Want to write the branch attribute to the product so we can
    # make sure we have no concerns about if a feature branch was used
    # to do the build or if the branch specifically for the version was 
    # used to do the build.
    $xml.version.source.branch = "$vcsBranch"
    $xml.version.source.revision = "$vcsRevision"
    
    $fileNode = $xml.version.file
    $fileNode.revision = $Script:buildNumber.ToString()
    $fileNode.date = $now.ToString("o")

    Write-Host "Set-VersionFromXml in $path file - commit $vcsRevision on branch $vcsBranch at $now for build number $($Script:buildNumber)"
    
    $xml.Save($path)
}

function Invoke-SlnBuild {
    param (
        [String]$Solution,
        [String[]]$Target
    )
    Invoke-Build -Task $Target -File "$root\$Solution\$Solution.build.ps1" 
}

function Move-SolutionArtifacts {

    foreach ($_ in $Solutions) {
        # if the sln created a directory for the package task then copy it over to the 
        # root's package
        if (Test-Path "$root\$_\.build\artifacts\package") {
            Move-DirectoryContent -Path "$root\$_\.build\artifacts\package" -Destination $rootArtifactsPath
        }
    }
    
    if (Test-Path "$root\version.xml"){
        Copy-Item -Path "$root\version.xml" -Destination "$rootArtifactsPath\version.xml"
    }
}

function Move-ToReleaseFolder {

    # If this structure changes then buildserver-utils/dev/IdentityServer4/copy-to-qa-download.ps1 needs
    # to be updated.
    $childPath = (Combine-Paths -Paths "releases", "$ProductName")

    $releasePath = (Join-Path -Path (Get-Location).Drive.Root -ChildPath "$childPath")
    $releaseOutputPath = (Join-Path -Path $releasePath -ChildPath "$vcsBranch-$BuildType")
    if (!(Test-Path -Path $releasePath)){
        Write-Host "creating directory $releaseOutputPath"
        New-Item -Path $releaseOutputPath -ItemType "directory"
    }
    
    Write-Host "moving files from $rootArtifactsPath for $BuildType to release folder $releaseOutputPath"
    Move-DirectoryContent -Path $rootArtifactsPath -Destination $releaseOutputPath
}

function Move-DirectoryContent {
    param (
        [string]$Path,
        [string]$Destination
    )

    Write-Host "moving $Path to $Destination"

    $p1 = (Resolve-Path -Path $Path)
    $p2 = (Resolve-Path -Path $Destination)

    Get-ChildItem -Path "$p1" -File -Recurse |
        ForEach-Object -Process {
            $destFilePath = $_.FullName.Replace($p1, $p2)
            $destFolderPath = [System.IO.Path]::GetDirectoryName($destFilePath)

            if (!(Test-Path -Path $destFolderPath)) {
                New-Item -Path $destFolderPath -ItemType 'Directory'
            }

            Write-Host "moving $($_.FullName) to $destFilePath"
            Move-Item -Path $_.FullName -Destination $destFilePath
        }
}

function Commit-VCS {
    # add the tracked files that have been modified to the staging are
    # and commit the changes
    git commit -a -m "$BuildType build from revision $vcsRevision"

    # want the revision to be 2 chars 
    $tag = "$($ProductVersion.ToString(3)).$($buildNumber.ToString('D2'))"

    # Only do this for CaseMax because don't need a tag in Firm specific 
    # repositories because they have such little code modifications.
    # Add the tag for the build so we can have an easy way to identify what
    # the source code looked like in a specific build
    if ($CompanyName -eq 'CaseMaxSolutions'){
        git tag -a "$tag" -m "build performed on $Env:COMPUTERNAME"
    }

    # pull (fetch and merge) the most recent changes - if there has been any other 
    # changes pushed from any other client we need to get those and then merge them 
    # into the changeset just created by the rc build
    git pull

    # push the commits to the server 
    git push 
    
    # Only CaseMax will add a tag - so push the just created tag
    if ($CompanyName -eq 'CaseMaxSolutions'){
        git push origin "$tag"
    }
}

function Delete-NuGetGlobalPackages {
    param (
        [String]$Solution,
        [string]$VersionPrefix
    )
    
    # Need to find out where the NuGet global-packages cache is because there are several
    # ways to have it not be in the default location.
    $path = Join-Path -Path $root -ChildPath ".external-bin\NuGet\nuget"
    if (Test-Path -Path $path){
        $output = (& "$path" locals global-packages -list)
    }
    else {
        $output = (dotnet nuget locals global-packages --list)
    }
    $path = $output.Replace('global-packages: ', '')

    # this path will not exist on machines that have not used NuGet to pull down packages
    if (Test-Path -Path $path){
        # get all of the projects contained in the sln directory by looking 2 sub folders
        # below the current solution directory for the csproj
        # .\{solution}\src\{project}\{project}.csproj
        $projFiles = (Get-ChildItem -Path "$root\$Solution" -Depth 2 -Filter "*proj")
        
        # NuGet.exe does not provide a way to ask it to delete packages following a certain
        # pattern - it only has a delete everything.  Doing that would force downloading of
        # many NuGet packages that are stable and don't need to be downloaded again.
        $projFiles |
            ForEach-Object {
               $f = [System.IO.Path]::GetFileNameWithoutExtension($_.FullName)
               # not every csproj will generate a nuget package
               if (Test-Path -Path "$path\$f\$VersionPrefix*")
               {
                   Get-ChildItem -Path "$path\$f\$VersionPrefix*" |
                           ForEach-Object { Remove-Directory -Path $_.FullName }
               }
            }
    }
}
