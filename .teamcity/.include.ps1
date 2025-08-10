# this is set to the environment variable on the machine running the build.  This
# key is sensitive because it allows for full permission to the file container 
$softwareLibraryWriteToken = $env:azure_software_library_write_token

# This is the name of the storage account in the Azure Portal
$storageAcctName = 'casemaxdata01'
$containerName = 'software-library'

Write-Host "checking to see if Az.Accounts module is installed"
if (!(Get-Module -Name 'Az.Accounts' -ListAvailable | Where-Object {$_.Version -eq '2.10.2'})) {
    Write-Host 'installing Az.Accounts 2.10.2 module'
    Install-Module -Name 'Az.Accounts' -RequiredVersion '2.10.2' -Scope CurrentUser -Confirm:$false -Force
}

Write-Host "checking to see if Az.Storage module is installed"
if (!(Get-Module -Name 'Az.Storage' -ListAvailable | Where-Object {$_.Version -eq '4.10.0'})) {
    Write-Host 'installing Az.Storage 4.10.0 module'
    Install-Module -Name 'Az.Storage' -RequiredVersion '4.10.0' -Scope CurrentUser -Confirm:$false -Force
}

Import-Module Az.Accounts -RequiredVersion '2.10.2'
Import-Module Az.Storage -RequiredVersion '4.10.0'

Write-Host "initializing connection to Azure Storage Account $storageAcctName"

#This will create a context to the Url 'https://casemaxdata01.blob.core.windows.net'
# [Microsoft.WindowsAzure.Commands.Storage.AzureStorageContext]
$storageCtx = New-AzStorageContext -SasToken $softwareLibraryWriteToken -StorageAccountName $storageAcctName

function Copy-BinariesToAzureSoftwareLibrary {
    param (
        [string]$SourceFile
    )

    $path = (Resolve-Path -Path $SourceFile)
    $filename = [System.IO.Path]::GetFileName($path)

    Write-Host "upload $SourceFile to container $($storageCtx.BlobEndPoint)"

    Set-AzStorageBlobContent -File "$path" `
        -Blob $filename `
        -Container $containerName `
        -Context $storageCtx

}
