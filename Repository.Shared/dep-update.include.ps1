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
            -Value '<?xml version="1.0" encoding="utf-8"?><configuration><packageSources /></configuration>' `
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