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

function Get-LocalCachePath {
    # this local directory will be used if present to save traffic to/from Azure because
    # that is much slower than pulling from a local file
    $localCachePath = $softwareLibraryPath

    if (!(Test-Path -Path $localCachePath)) {
        Write-Host "did not find $localCachePath on current disk - so using directory in user profile"
        $userprofile = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
        $localCachePath = Join-Path $userprofile ".software-library"

        if (!(Test-Path -Path $localCachePath)){
            Write-Host "creating $localCachePath on current disk to cache software-library downloads"
            New-Item -Path $localCachePath -ItemType Directory | Out-Null
        }
    }

    Write-Output $localCachePath
}

function Download-AzCopy {
    # Downloading AzCopy from MS website and extract it locally.  Doing it this way so don't have to
    # worry about installing software on build servers or developer workstations.  Using AzCopy
    # instead of Blob APIs because it is more effecient when working with large files

    $localCachePath = (Get-LocalCachePath)

    $lastCheckedAt = [System.DateTime]::MinValue

    $azCopyInfoPath = [System.IO.Path]::Combine($localCachePath, "AzCopy-info.txt")
    if (Test-Path -Path $azCopyInfoPath) {
        Write-Host "reading last time AzCopy was checked for new version"
        $lastCheckedAt = [System.DateTime]::Parse((Get-Content -Path $azCopyInfoPath))
    }

    if ($lastCheckedAt.AddDays(7) -gt [System.DateTime]::Now){
        Write-Host "AzCopy was last checked at $lastCheckedAt - that falls within the last week - not downloading again"
    }
    else {
        if ($IsLinux){
            Write-Host "downloading AzCopy v10 for Linux into local cache"
            Invoke-WebRequest -Uri "https://aka.ms/downloadazcopy-v10-linux" `
                -OutFile "$localCachePath/AzCopy-10.0.tar" `
                -UseBasicParsing
        }
        else {
            Write-Host "downloading AzCopy v10 for Windows into local cache"
            Invoke-WebRequest -Uri "https://aka.ms/downloadazcopy-v10-windows" `
                -OutFile ([System.IO.Path]::Combine($localCachePath, 'AzCopy-10.0.zip')) `
                -UseBasicParsing
        }

        Write-Host "updating AzCopy-info.txt"
        Set-Content -Path $azCopyInfoPath -Value (Get-Date)
    }

    # tar needs to have the directory present to extract it to a specific dir
    $azCopyDirPath = [System.IO.Path]::Combine($localCachePath, 'AzCopy')
    if (!(Test-Path -Path $azCopyDirPath)){
        Write-Host "creating $azCopyDirPath to extract downloaded AzCopy into"
        New-Item -Path $azCopyDirPath -ItemType Directory | Out-Null
    }

    if ($IsLinux){
        Write-Host "extracting downloaded AzCopy v10 tar from local cache into $azCopyDirPath"
        # tar will write out the files it extracts and it will be interpreted as Write-Ouptut
        # and mess up the path to $azCopyExe that is returned
        tar -C "$azCopyDirPath/" -xvf $localCachePath/AzCopy-10.0.tar | Out-Null
        
        $azcopySearchPath = [System.IO.Path]::Combine($azCopyDirPath, 'azcopy_linux*', 'azcopy')
    }
    else {
        Write-Host "extracting downloaded AzCopy v10 zip from local cache into $azCopyDirPath"
        Expand-Archive -Path ([System.IO.Path]::Combine($localCachePath, 'AzCopy-10.0.zip')) `
                -DestinationPath $azCopyDirPath `
                -Force
        
        $azcopySearchPath = [System.IO.Path]::Combine($azCopyDirPath,'azcopy_windows*', 'azcopy.exe')
    }

    $azcopyExe = (Get-ChildItem -Path "$azcopySearchPath" | 
        Sort-Object -Property LastWriteTime |
        Select-Object -Last 1).FullName

    Write-Host "use AzCopy.exe at $azcopyExe"
    Write-Output $azcopyExe
}

function Copy-BinariesToAzureSoftwareLibrary {
    param (
        [string]$SourceFile
    )

    $path = (Resolve-Path -Path $SourceFile)
    $filename = [System.IO.Path]::GetFileName($path)
    $destUrl = "$softwareLibraryUrl/$filename$softwareLibraryWriteToken"

    $azCopyExe = (Download-AzCopy)

    Write-Host "upload $SourceFile as $filename to container $softwareLibraryUrl"
    & "$azCopyExe" cp `
        "$path" `
        "$destUrl"

}