param(
    $BuildType = (property BuildType 'dev')
)

Set-Alias -Name MSBuild (Resolve-MSBuild 17.0)

$slnName = 'IdentityServer4'
$bitness = 'x64'

$vsConfiguration = 'Debug'
$vsBinPath = 'bin\Debug'

if (@('nightly', 'beta', 'rc') -contains $BuildType) {
    $vsConfiguration = 'Release'
    $vsBinPath = 'bin\Release'
}

#include shared functions for solutions
. ..\Repository.Shared\sln.include.ps1

Add-BuildTask -Name Clean -Jobs {
    Clean-DotNet -Solution $slnName -VsConfiguration $vsConfiguration
}

Add-BuildTask -Name Build -Jobs {
    Build-DotNet -Solution $slnName -VsConfiguration $vsConfiguration
}

Add-BuildTask -Name Setup -Jobs {
    # nothing to do, no running apps
}

Add-BuildTask -Name Test -Jobs {
    Invoke-DotNetTest -Project "IdentityServer.UnitTests" -VsConfiguration $vsConfiguration
    Invoke-DotNetTest -Project "IdentityServer.IntegrationTests" -VsConfiguration $vsConfiguration
    
    Invoke-DotNetTest -Project "IdentityServer4.EntityFramework.UnitTests" -VsConfiguration $vsConfiguration
    Invoke-DotNetTest -Project "IdentityServer4.EntityFramework.IntegrationTests" -VsConfiguration $vsConfiguration
}

Add-BuildTask -Name Package -Jobs {

    <#
    $packagePath = '.\.build\artifacts\package'
    $slnPath = "$packagePath\CaseMaxSolutions\PRS.Aspose\"

    New-Directory -Path "$packagePath\CaseMaxSolutions"
    New-Directory -Path "$slnPath"
    New-Directory -Path "$slnPath\bin"

    Package-Exe -Project 'PRS.Aspose.DocumentExplorer' -VsBinPath $vsBinPath -Destination $slnPath
    Package-Exe -Project 'PRS.Aspose.CLI' -VsBinPath "$vsBinPath\net472" -Destination $slnPath
    #>

}
