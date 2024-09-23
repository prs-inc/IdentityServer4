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

function Copy-BinariesToAzureSoftwareLibrary {
    param (
        [string]$AzCopyExe,
        [string]$SourceFile
    )

    $path = (Resolve-Path -Path $SourceFile)
    $filename = [System.IO.Path]::GetFileName($path)
    $destUrl = "$softwareLibraryUrl/$filename$softwareLibraryWriteToken"

    Write-Host "upload $SourceFile as $filename to container $softwareLibraryUrl"
    & "$AzCopyExe" cp `
        "$path" `
        "$destUrl"

}
