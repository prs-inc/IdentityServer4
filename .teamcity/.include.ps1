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