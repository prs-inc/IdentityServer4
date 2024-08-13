# this is set to the environment variable on the machine running the build.  This
# key is sensitive because it allows for full permission to the file container 
$softwareLibraryWriteToken = $env:azure_software_library_write_token

# location of the software-library directory on either Azure Blob Container or local cache on Server
$softwareLibraryUrl = 'https://casemaxdata01.blob.core.windows.net/software-library'

# this local directory will be used if present to save traffic to/from Azure because
# that is much slower than pulling from a local file
if ($null -ne $env:SOFTWARE_LIBRARY){
    $softwareLibraryPath = $env:SOFTWARE_LIBRARY
    Write-Host "SOFTWARE_LIBRARY in env variable is $softwareLibraryPath"
}
else {
    $softwareLibraryPath = Join-Path ((Get-Location).Drive.Root) ".software-library"
    Write-Host "no env variable for SOFTWARE_LIBRARY - using path on local drive $softwareLibraryPath"
}

function Find-AzCopy {
    
    # the AzCopy executable should have already been downloaded into the .external-bin directory
    $azCopyExtBinPath = [System.IO.Path]::Combine($PSScriptRoot, '..', '.external-bin', 'AzCopy')

    if ($IsLinux){
        $azcopySearchPath = [System.IO.Path]::Combine($azCopyExtBinPath, 'azcopy_linux*', 'azcopy')
    }
    else {
        $azcopySearchPath = [System.IO.Path]::Combine($azCopyExtBinPath,'azcopy_windows*', 'azcopy.exe')
    }

    # search for the exe and get the one with the most recent LastWriteTime - should only be one because
    # the .external-bin should be cleaned before and after each build
    $azcopyExe = (Get-ChildItem -Path "$azcopySearchPath" | 
        Sort-Object -Property LastWriteTime |
        Select-Object -Last 1).FullName

    Write-Host "use AzCopy.exe at $azcopyExe"
    Write-Output $azcopyExe
}


function Copy-BinariesToLocalCacheSoftwareLibrary {
    param (
        [string]$SourceFile
    )

    $filename = [System.IO.Path]::GetFileName($SourceFile)

    $destPath = "$softwareLibraryPath\$filename"
    Write-Information "copying from $SourceFile to $destPath for $branch.$revision"
    Copy-Item -Path $SourceFile -Destination $destPath -Force
}

function Copy-BinariesToAzureSoftwareLibrary {
    param (
        [string]$SourceFile
    )

    $path = (Resolve-Path -Path $SourceFile)
    $filename = [System.IO.Path]::GetFileName($path)
    $destUrl = "$softwareLibraryUrl/$filename$softwareLibraryWriteToken"

    $azCopyExe = (Find-AzCopy)

    Write-Host "upload $SourceFile as $filename to container $softwareLibraryUrl"
    & "$azCopyExe" cp `
        "$path" `
        "$destUrl"

}

function Copy-BinariesToSoftwareLibrary {
    param (
        [string]$SourceFile,
        [string]$BuildType
    )

    # Only the build servers will ever need the 'rc' builds so we can save the time of uploading
    # to and downloading from Azure.  The rc builds for each Firm are run on the same server as 
    # the CaseMax rc build so we don't need the rc builds out on Azure, just in the local cache.
    # The other build types will end up having copies made to the
    # local cache by dep-update.include.ps1.  It has logic to sync the local share copy with the copy
    # in Azure if it finds that Azure copy is newer than local cache copy.
    if ($BuildType -eq 'rc'){
        Write-Information 'copying the rc build out to the local cache software-library directory'
        Copy-BinariesToLocalCacheSoftwareLibrary -SourceFile $SourceFile
    }
    else {
        Write-Information "copying the $BuildType build out to Azure software-library"
        Copy-BinariesToAzureSoftwareLibrary -SourceFile $SourceFile
    }
}
