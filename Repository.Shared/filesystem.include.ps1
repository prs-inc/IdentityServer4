# THIS FILE IS NOT MEANT TO BE USED DIRECTLY 

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

    Remove-Directory -Path $Path
    
    New-Item -Path $Path -ItemType "Directory"
}
