# THIS FILE IS NOT MEANT TO BE USED DIRECTLY 

function Create-EventSource($sourceName){

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

