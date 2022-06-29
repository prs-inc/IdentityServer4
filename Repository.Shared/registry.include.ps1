# THIS FILE IS NOT MEANT TO BE USED DIRECTLY 

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
