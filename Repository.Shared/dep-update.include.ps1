# THIS FILE IS NOT MEANT TO BE USED DIRECTLY 
# it should be included in dependencies-update.ps1 at the root
. ([System.IO.Path]::Combine($PSScriptRoot, 'filesystem.include.ps1'))

# need to make sure PowerShell is using latest security protocol on older OS versions
# to make http requests. The old SSL3 will fail on most https based connections - such 
# as the one to https://aka.ms
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# the SilentlyContinue improves performance because it allows the use of the -Name parameter that
# will find the package provider for the majority of cases where it is already installed.
Write-Host "checking to see if NuGet package provider is installed"
if ($null -eq (Get-PackageProvider -Name 'NuGet' -ListAvailable -ErrorAction SilentlyContinue)){
    Install-PackageProvider -Name 'NuGet' -MinimumVersion 2.8.5.201 -Force
}

# This is an MS run repository so pretty sure we can trust it and get rid of the prompts asking
# if we trust it.
if ($null -eq (Get-PSRepository |Where-Object {$_.Name -eq 'PSGallery' -and $_.InstallationPolicy -eq 'Trusted'})) {
    Write-Host "trusting PSGallery to install packages from"
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
}

function Add-NuGetPackageSource {
    param(
        [string]$Name,
        [string]$Path
    )

    # need to use the Resolve-Path because need the full path for XmlDocument
    # operations since .net interop code will be running in a different directory
    if (!(Test-Path -Path 'NuGet.config')){
        Set-Content -Path 'NuGet.config' `
            -Value '<?xml version="1.0" encoding="utf-8"?>
            <configuration>
                <packageSources>
                    <clear />
                    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
                </packageSources>
            </configuration>' `
            -Encoding 'utf8'
    }
    
    $configFilePath = (Resolve-Path -Path 'NuGet.config')
    $doc = [xml](Get-Content -Path $configFilePath)

    # want to get rid of the current directory if the $Version that was downloaded is different
    # than the version that is on disk.  
    $sourcesEl = $doc.SelectSingleNode("//configuration/packageSources")
    $el = $sourcesEl.SelectSingleNode("add[@key='$Name']")
    if ($el -eq $null){
        Write-Host "did not find file node with attribute product containing value $Product"
        $el = $doc.CreateElement("add")
        $el.SetAttribute("key", $Name)
    }
    
    $el.SetAttribute("value", $Path)
    $sourcesEl.AppendChild($el)
    $doc.Save("$configFilePath")
}

function Download-AzCopy {
    # Downloading AzCopy from MS website and extract it locally.  Doing it this way so don't have to
    # worry about installing software on build servers or developer workstations.  Using AzCopy
    # instead of Blob APIs because it is more effecient when working with large files
    $lastCheckedAt = [System.DateTime]::MinValue

    $azCopyInfoPath = Combine-Paths -Paths $localCachePath, "AzCopy-info.txt"
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
                -OutFile (Combine-Paths -Paths $localCachePath, 'AzCopy-10.0.zip') `
                -UseBasicParsing
        }

        Write-Host "updating AzCopy-info.txt"
        Set-Content -Path $azCopyInfoPath -Value (Get-Date)
    }

    # tar needs to have the directory present to extract it to a specific dir
    $azCopyDirPath = Combine-Paths -Paths '.external-bin', 'AzCopy'
    if (!(Test-Path -Path $azCopyDirPath)){
        Write-Host "creating $azCopyDirPath to extract downloaded AzCopy into"
        New-Item -Path $azCopyDirPath -ItemType Directory | Out-Null
    }

    if ($IsLinux){
        Write-Host "extracting downloaded AzCopy v10 tar from local cache into .external-bin"
        # tar will write out the files it extracts and it will be interpreted as Write-Ouptut
        # and mess up the path to $azCopyExe that is returned
        tar -C ./.external-bin/AzCopy/ -xvf $localCachePath/AzCopy-10.0.tar | Out-Null
        
        $azcopySearchPath = "./.external-bin/AzCopy/azcopy_linux*/azcopy"
    }
    else {
        Write-Host "extracting downloaded AzCopy v10 zip from local cache into .external-bin"
        Expand-Archive -Path (Combine-Paths -Paths $localCachePath, 'AzCopy-10.0.zip') `
                -DestinationPath $azCopyDirPath `
                -Force
        
        $azcopySearchPath = Combine-Paths -Paths '.external-bin', 'AzCopy', 'azcopy_windows*', 'azcopy.exe'
    }

    $azcopyExe = (Get-ChildItem -Path "$azcopySearchPath" | 
        Sort-Object -Property LastWriteTime |
        Select-Object -Last 1).FullName

    Write-Output $azcopyExe
}