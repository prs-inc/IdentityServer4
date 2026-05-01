# THIS FILE IS NOT MEANT TO BE USED DIRECTLY
# It should have been a Module (psm1) but the exec {} provided by Invoke-Build is not being recognized and
# PowerShell is returning an error.  It is more conceptually a module but there is obviously some concept
# about modules that I am missing with how they access other modules that have already been imported into
# the current PowerShell sessions.  So back to the primitive dot sourcing to include files.

# need to make sure these assmeblies are loaded in the powershell process
if ($PSEdition -eq 'Desktop') {
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
}

function Add-EventSource($sourceName){

    if (-Not ([System.Diagnostics.EventLog]::SourceExists($sourceName))) {
        [System.Diagnostics.EventLog]::CreateEventSource($sourceName, 'CaseMaxSolutions')
    }
}

function Test-CommandExists {
    param (
        [String]$Name
    )
    $cmd = Get-Command -Name $Name -ErrorAction 'SilentlyContinue'
    return ($null -ne $cmd)
}

function Test-RegistryKeyValue {
    param(
        [string]$Path,
        [string]$Name
    )

    if (-not (Test-Path -Path $Path -PathType Container)) {
        return $false
    }

    $values = (Get-ItemProperty -Path $Path)
    if (-not $values){
        return $false
    }

    return ($values.PSObject.Properties.Name -contains $Name)
}

function Combine-Paths {
    param (
        [String[]]$Paths
    )

    [System.IO.Path]::Combine($Paths)
}

function Remove-File {
    param (
        [String]$Path
    )

    # if the file doesn't exist then error is output to console when Remove-Item is called
    if (Test-Path -Path $Path) {
        Remove-Item -Path $Path -ErrorAction Continue
    }
}

function Remove-Directory {
    param (
        [String]$Path
    )

    if (Test-Path -Path $Path) {
        # don't know why I have to fall back to using CMD.EXE, but
        # that is the game we play with PowerShell - find out why a seemingly obvious thing
        # should just work only to find out there is problem affecting a -Item command.
        if ($IsLinux -eq $true){
            rm -r "$Path"
        }
        else {
            cmd.exe /c rd /s /q "$Path"
        }
    }
}

function New-Directory {
    param (
        [String]$Path
    )

    # sending this out to null because don't want the output from the Remove-Directory to be returned in
    # the pipeline - just want the new directory
    Remove-Directory -Path $Path | Out-Null

    New-Item -Path $Path -ItemType "Directory"
}

function Add-ProgramDataDir {
    param (
        [string]$Path,
        [switch]$KeepExisting
    )

    $fullpath = $env:ProgramData + $Path

    if ($KeepExisting -eq $false) {
        Remove-Directory -Path $fullpath
    }

    # the previous delete might not have fully deleted it because there could be a
    # running process that has a hold of a file in one of the subdirectories
    if ((Test-Path -Path $fullpath) -eq $false) {
        New-Item $fullpath -ItemType Directory
    }
}

function Compress-NuGetPackage {
    param (
        [string]$Path,
        [string]$DestinationPath
    )

    # need to use a temporary zip file because Expand-Archive ONLY works with .zip files
    $p = "$Path.zip"

    Write-Host "compressing directory $Path into NuGetPackage $DestinationPath"

    # need to add the [Content_Types].xml file first and then the _rels directory to follow along with the expected
    $paths = (Combine-Paths -Paths $Path, '`[Content_Types`].xml'), (Combine-Paths -Paths $Path, '_rels')
    Compress-Archive -Path $paths -DestinationPath $p
    Remove-Item -Path $paths -Recurse -Force

    # now we can update the rest of the zip file because it doesn't matter the order the content is added
    Compress-Archive -Path (Combine-Paths -Paths $Path, '*') `
        -DestinationPath $p `
        -Update

    Move-Item -Path $p -Destination $DestinationPath

}

function Expand-NuGetPackage {
    param (
        [string]$Path,
        [string]$DestinationPath
    )

    # need to use a temporary zip file because Expand-Archive ONLY works with .zip files
    $p = "$Path.zip"
    Copy-Item -Path $Path -Destination $p

    Write-Host "expanding NuGetPackage $Path into directory $DestinationPath"
    Expand-Archive -Path $p -DestinationPath $DestinationPath -Force

    Remove-Item -Path $p

}

function Set-DigitalSignature {
    param(
        [string]$Endpoint = ($env:CodeSigningEndpoint),
        [string]$Account = ($env:CodeSigningAccount),
        [string]$CertProfile = ($env:CodeSigningCertProfile),
        [string]$Path,
        [string[]]$Include = @('PRS.*.dll', 'PRS.*.exe'),
        [switch]$UseUTCForLastWriteTime
    )

    if ([System.String]::IsNullOrEmpty($Endpoint)){
        # this should only occur on the developer workstations
        Write-Host "not signing files in path $Path - Endpoint was not set."
        return
    }

    if ([System.String]::IsNullOrEmpty($Account)){
        Write-Host "not signing files in path $Path - Account was not set."
        return
    }

    if ([System.String]::IsNullOrEmpty($CertProfile)){
        Write-Host "not signing files in path $Path - CertProfile was not set."
        return
    }

    # get all of the files in the directory - assuming it is a directory containing build output
    $paths = @(Get-ChildItem -Path $Path -Include $Include -Recurse |
        Get-AuthenticodeSignature |
        Where-Object { $_.Status -eq 'NotSigned'} |
        Select-Object -ExpandProperty 'Path')

    Write-Host "signing $($paths.Length) files in $Path with certificate $CertProfile in Artifact Signing Account $Account at Uri $Endpoint"

    # need to call dotnet.exe for each path, passing in all the paths was causing a build error
    # 'The filename or extension is too long'
    foreach ($path in $paths){
        exec {
            dotnet sign code artifact-signing `
                --artifact-signing-endpoint $Endpoint `
                --artifact-signing-account $Account `
                --artifact-signing-certificate-profile $CertProfile `
                --azure-credential-type 'managed-identity' `
                --timestamp-url 'http://timestamp.digicert.com' `
                --verbosity 'Information' `
                $path
        }

        # Then AzureSignTool modifies the dll/exe when it adds the Digital Signature to it and uses local time
        # for the Modified Time.  Some other formats (such as files added to nupkg) want the File's Modified
        # Time to be in UTC time
        if ($UseUTCForLastWriteTime) {
            $f = Get-ChildItem -Path $path
            $f.LastWriteTime = $f.LastWriteTime.ToUniversalTime()
        }
    }
}

function Set-NuGetContentsDigitalSignature {
    param(
        [string]$Endpoint = ($env:CodeSigningEndpoint),
        [string]$Account = ($env:CodeSigningAccount),
        [string]$CertProfile = ($env:CodeSigningCertProfile),
        [string]$Path,
        [string]$Prefix
    )

    $p = (Resolve-Path -Path $Path).Path

    if ([System.String]::IsNullOrEmpty($Endpoint)){
        # this should only occur on the developer workstations
        Write-Host "not signing NuGet packages in path $p - Endpoint was not set."
        return
    }

    if ([System.String]::IsNullOrEmpty($Account)){
        Write-Host "not signing NuGet packages in path $p - Account was not set."
        return
    }

    if ([System.String]::IsNullOrEmpty($CertProfile)){
        Write-Host "not signing NuGet packages in path $p - CertProfile was not set."
        return
    }

    # If this file does not exists then create it so we can keep track of all the nuget packages
    # that have had their content signed.  Many solution files have csproj files in them that are not
    # prefixed with the solution name so the prefix has to be more general like 'PRS' or 'PRS.CMS'.
    # The _signed.txt keeps track of signed nupkg files so we don't process the same one twice from
    # different solutions
    if (!(Test-Path -Path "$p\_signed.txt")) {
        New-Item -Path "$p\_signed.txt" -ItemType File
    }

    $signedFiles = Get-Content -Path "$p\_signed.txt"

    # get the nupkg files in this directory that have not had their contents signed before
    $nupkgFiles = @(Get-ChildItem -Path "$p\$Prefix.*.nupkg" |
        Where-Object {$signedFiles -notcontains [System.IO.Path]::GetFileNameWithoutExtension($_.FullName)} |
        Select-Object -ExpandProperty 'FullName')

    # iterate through each file - rename the .nupkg files into .zip and extract their contents.  Then sign
    # the contents that were extracted.  Then zip that directory back up and change the extension back to
    # .nupkg.  Clean up the resources and make a note of having signed the .nupkg file.
    Write-Host "going to sign contents of nupkg files"
    
    $nupkgFiles |
        ForEach-Object {
            $packageName = [System.IO.Path]::GetFileNameWithoutExtension($_)
            Write-Host "going to sign contents of $packageName"
            
            dotnet sign code artifact-signing `
                --artifact-signing-endpoint $Endpoint `
                --artifact-signing-account $Account `
                --artifact-signing-certificate-profile $CertProfile `
                --azure-credential-type 'managed-identity' `
                --timestamp-url 'http://timestamp.digicert.com' `
                --verbosity 'Information' `
                --recurse-containers `
                $_
            
            Add-Content -Path "$p\_signed.txt" -Value $packageName
            
        }
}

function Zip-Directory {
    param (
        [string]$Path,
        [string]$Destination,
        [System.IO.Compression.CompressionLevel]$CompressionLevel = 'Optimal'
    )

    # The Compress-Archive is painfully slow when it outputs its progress to the screen.  It goes from 1 or 2 seconds to create the export.zip file
    # to 20+ seconds.

    # need to make sure the Path & Destination have values that are full paths because calling into .net code has different path resolution
    $p = Resolve-Path -Path $Path

    # need a file to exist to be able to call Resolve-Path on it
    if (!(Test-Path -Path $Destination)){
        New-Item -Path $Destination | Out-Null
    }
    $d = Resolve-Path -Path $Destination

    # now that we have the full path to the zip that will be created we can go ahead and delete it and let the ZipFile write it
    Remove-Item -Path $Destination

    Write-Host "zipping the contents in directory $p into the file $d"
    [System.IO.Compression.ZipFile]::CreateFromDirectory($p, $d, $CompressionLevel, $false)
}
