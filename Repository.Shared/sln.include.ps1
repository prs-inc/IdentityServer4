# THIS FILE IS NOT MEANT TO BE USED DIRECTLY 
# It should be included in any build for VS solutions.

Write-Host "the current location is " (Get-Location)
$rootPath = (Resolve-Path -Path '..')

# include shared functions for file system
# since this is a nested dot source it has to be done from the location of the 
# current root file
. ([System.IO.Path]::Combine($rootPath, 'Repository.Shared', 'filesystem.include.ps1'))

function Set-MSBuildAlias {
    param (
        [string]$Version
    )
    
    if ($IsLinux -eq $true){
        # this is not using any specific version, just the latest one in the path
        # this should be irreleveant because all Linux builds should be using dotnet.exe
        # instead of the Mono version of msbuild
        $path = "/usr/bin/msbuild"
    }
    else {
        $path = (Resolve-MSBuild $Version)
    }
    
    Set-Alias -Name MSBuild $path -Scope Global
}

function Remove-CompilerFiles {
    # MSBuild Clean leaves behind files that it did not create
    Remove-Item -Path '.\src\*\bin\*' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path '.\src\*\obj\*' -Recurse -Force -ErrorAction SilentlyContinue
    
    # some sln seperate out the src and test into seperate directories
    if (Test-Path -Path '.\test') {
        Remove-Item -Path '.\test\*\bin\*' -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path '.\test\*\obj\*' -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Remove-CodeAnalysisOutputFiles {
    Remove-Item -Path ".\src\*\bin\*" -Include "*.CodeAnalysisLog.xml" -Recurse
    Remove-Item -Path ".\src\*\bin\*" -Include "*.lastcodeanalysis*" -Recurse

    # some sln seperate out the src and test into seperate directories
    if (Test-Path -Path '.\test') {
        Remove-Item -Path ".\test\*\bin\*" -Include "*.CodeAnalysisLog.xml" -Recurse
        Remove-Item -Path ".\test\*\bin\*" -Include "*.lastcodeanalysis*" -Recurse
    }
}

function Restore-NuGet {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $Solution
    )
    $path = Join-Path -Path $rootPath -ChildPath ".external-bin\NuGet\nuget"
    Write-Host "restoring with nuget at $path"

    exec {
        & "$path" restore "$Solution.sln"
    }  
}

function Invoke-DotNetTest {
    param (
        [string]$Project,
        [string]$VsConfiguration,
        [string]$TFM = ''
    )
    
    $csproj = (Get-ChildItem -Path ".\*\$Project" -Filter "$Project.csproj" -Recurse)

    exec {

        $args = @()

        $args += "$csproj"
        $args += "--no-build"
        $args += "--configuration"
        $args += "$VsConfiguration"
        if ($TFM -ne ''){
            $args += "--framework"
            $args += "$TFM"
        }
        $args += '--logger'
        $args += '"console;verbosity=normal"'
        
        # RunSettings
        $args += "--"
        $args += "NUnit.DisplayName=FullNameSep"
        
        Write-Host $args
        dotnet test $args
    }

}

function Invoke-NUnit {
    param (
        [String[]]$Project,
        [String]$WorkingPath,

        [ValidateSet('x86', 'x64')]
        [String]$Bitness = 'x64'
    )

    $nunit = (Resolve-Path -Path '..\.external-bin\NUnit.ConsoleRunner\tools\nunit3-console.exe')

    Set-Location -Path $WorkingPath
    exec {
        $args = @()
        foreach ($proj in $Project){
            $args += "$proj.dll"
        }

        $args += "--result=.nunit-test-results.xml"
        $args += '--framework="net-4.5"'
        $args += '--labels=All'

        # need to add a parameter if we are running x86
        if ($Bitness -eq 'x86') {
            $args += "--x86"
        }
        
        & "$nunit" $args
    }
    
    Set-Location $BuildRoot
    
}

function Invoke-KarmaTestRunner {
    param (
        [string]$Project
    )

    Set-Location -Path ".\src\$Project"
    exec {
        & node ".\node_modules\karma\bin\karma" start karma.conf.js --single-run
    }

    Set-Location -Path $BuildRoot
}

function Invoke-XmlDoc2CmdletDoc {
    param (
        [String]$Project,
        [String]$VsBinPath
    )
    
    $docExe = Resolve-Path -Path "$rootPath\.external-bin\XmlDoc2CmdletDoc\tools\XmlDoc2CmdletDoc.exe"

    exec {
        & $docExe ".\src\$Project\$vsBinPath\$Project.dll"
    }
}

function Package-Exe {
    param (
        [String]$Project,
        [String]$VsBinPath,
        [String]$Destination
    )

    if (!(Test-Path -Path "$Destination\bin")){
        New-Directory -Path "$Destination\bin"
    }

    Copy-Item -Path ".\src\$Project\$VsBinPath\*" -Destination $Destination -Recurse -Include "$Project.*" -Exclude "$Project.vshost.*" -Force
    Copy-Item -Path ".\src\$Project\$VsBinPath\*" -Destination "$Destination\bin" -Recurse -Exclude "$Project.*", '*.pssym' -Force
}

function Package-Directory {
    param (
        [String]$Project,
        [String]$VsBinPath,
        [String]$Destination
    )

    Write-Host "Path is .\src\$Project\$VsBinPath\*"
    Write-Host "Destination is $Destination"

    # If the destination does not exist then it needs to be created.  Not assuming we always
    # need to create it because some scripts will do that for us and will create a structure
    # they need.
    if (!(Test-Path -Path $Destination)) {
        New-Directory $Destination
    }
    
    Copy-Item -Path ".\src\$Project\$VsBinPath\*" -Destination $Destination -Recurse -Force 

    # get rid of PostSharp Symbol files, only needed for VS extension
    Get-ChildItem -Path "$Destination\*.pssym" -Recurse | Remove-Item
}

function Publish-DotNet {
    param (
        [String]$Project,
        [String]$VsConfiguration,
        [String]$Destination,
        [string]$TFM = 'netcoreapp3.1',
        [string]$RID = ''
    )

    Write-Host "dotnet publish for $Project using configuration $VsConfiguration"
    Write-Host "Destination is $Destination"
    
    New-Directory $Destination

    # Need the SolutionDir property because the .csproj files will output to 
    # $(SolutionDir).build\bin\...  Since this public target is a csproj there
    # is no $(SolutionDir) being set by MSBuild.  Need the trailing slash to
    # mimic exact path generated by MSBuild for .sln based builds.
    $slnDir = $(Resolve-Path '.')
    
    exec {
        $args = @(Combine-Paths -Paths 'src', $Project, "$Project.csproj")
        $args += "--configuration", "$VsConfiguration"
        $args += "--framework", "$TFM"
        $args += "--output", "$Destination"
        
        if ($RID -ne ''){
            $args += "--runtime", "$RID"
            # this mean the .net core runtime has to be installed on the machine these files are xcopied over to
            $args += "--self-contained", "false"
        }
        else {
            # If no RID is passed in then we can assume that the build output is good
            # and package can just use the previous build.
            $args += "--no-build"
        }
        
        if ($IsLinux){
            $args += "-p:SolutionDir=`"$slnDir/`""
        }
        else {
            # Need the \ at the end because the \" is treated by the cmd.exe as an escape of the quote - but
            # SolutionDir needs to end with a \ - so the double slash at the end of "path\foo\bar\\" is needed.
            $args += "-p:SolutionDir=`"$slnDir\\`""
        }

        Write-Host "dotnet publish $args"
        dotnet publish $args
    }
}

function Package-Web-AspNetCore {
    param (
        [String]$Project,
        [String]$VsConfiguration,
        [String]$Destination
    )

    Write-Host "Path is .\src\$Project\*"
    Write-Host "Destination is $Destination"

    New-Directory $Destination
    Write-Host "packaging exe AspNetCore for $Project"
    Package-Exe -Project $Project -VsBinPath "bin\$VsConfiguration\net472" -Destination $Destination

    # this is a VS compiler artificat used for NuGet
    Remove-Item -Path "$Destination\*.deps.json"

    # need the Web.config for IIS hosting
    Copy-Item -Path ".\src\$Project\Web.config" -Destination "$Destination\Web.config"

    # if this is just a web api or has no UI this folder might not exist
    if (Test-Path -Path ".\src\$Project\wwwroot") {
        # wwwroot contains the static assets
        Copy-Item -Path ".\src\$Project\wwwroot" -Destination $Destination -Recurse -Force
    }

    Write-Host "update web.config AspNetCore for $Project"
    Update-WebConfig-AspNetCore -Project $Project -Path "$Destination\Web.config" -VsConfiguration $VsConfiguration
}

function Update-WebConfig-AspNetCore {
    param (
        [string]$Project,
        [string]$Path,
        [string]$VsConfiguration
    )

    # need to use Resolve-Path because the working directory used by Xml.Save is
    # different than the current powershell directory
    $configPath = (Resolve-Path -Path $Path)
    $xml = [xml](Get-Content -Path $configPath)

    # <aspNetCore processPath="%LAUNCHER_PATH%" arguments="%LAUNCHER_ARGS%" stdoutLogEnabled="false">
    $node = $xml.SelectSingleNode("/configuration/system.webServer/aspNetCore")
    $node.SetAttribute("processPath", ".\$Project.exe")
    $node.SetAttribute("arguments", "")

    $xml.Save($configPath)
}

function Package-Web {
    param (
        [String]$Project,
        [String]$VsConfiguration,
        [String]$Destination
    )

    Write-Host "Path is .\src\$Project\*"
    Write-Host "Destination is $Destination"

    New-Directory $Destination
    Copy-Item -Path ".\src\$Project\*" -Destination $Destination -Recurse -Force `
        -Exclude 'node_modules', 'obj', 'Properties', 'Web References', '*.build', '*.cs', '*.cd', '*.csproj*', '*.pssym', '*.resx', '*.targets', 'gulpfile.js', 'json.config', 'packages.config', 'tsconfig.json'

    # get all of the directories, sorted by FullName so that child directories appear
    # before their parent directory
    $dirs = Get-ChildItem -Path $Destination -Directory -Recurse | 
        Sort-Object -Descending -Property FullName

    # iterate through the sorted directories to find any empty ones and delete it
    # if the directory is empty
    foreach($_ in $dirs) {
        $info = (Get-ChildItem -Path $_.FullName -Recurse -File) | Measure-Object
        
        if ($info.Count -eq 0) {
            Write-Host "removing empty directory $_"
            Remove-Item -Path $_.FullName -Force
        }
    }

    Update-WebConfig -Path "$Destination\Web.config" -VsConfiguration $VsConfiguration

}

function Update-WebConfig {
    param (
        [string]$Path,
        [string]$VsConfiguration
    )

    if ($VsConfiguration -eq 'Release'){
        # need to use Resolve-Path because the working directory used by Xml.Save is
        # different than the current powershell directory
        $configPath = (Resolve-Path -Path $Path)
        $xml = [xml](Get-Content -Path $configPath)

        $node = $xml.SelectSingleNode("/configuration/system.web/compilation")
        $node.SetAttribute("debug", "false")

        $xml.Save($configPath)
    }
}

function Copy-WorkpointConfigFile {
    param (
        [Parameter(Mandatory=$true)]
        [String]
        $Destination,
        
        [ValidateSet('Tcp', 'NamedPipe', 'WsHttp')]
        [String]
        $Protocol = 'Tcp'
    )
    
    Write-Host "copying protocol $Protocol config files if WorkpointBPMClient.dll exists in directory $Destination"
    # only copy if the Workpoint client dll is there even if the build file says to do it.
    if (Test-Path -Path "$Destination\WorkpointBPMClient.dll") {

        # assume this build is being done for CaseMax, but check the external-bin to see 
        # if a CMS directory exists
        $workpointServerPath = "..\.external-bin\Workpoint.NET\server"
        if (Test-Path -Path "..\.external-bin\CMS\Workpoint.NET"){
            $workpointServerPath = "..\.external-bin\CMS\Workpoint.NET"
        }

        $path = "$workpointServerPath\conf\WorkpointClient\$Protocol\WorkpointBPMClient.dll.config"
        Write-Host "copying protocol $protocol config files from $path"
        Copy-Item -Path $path -Destination "$Destination" -Force
    }
}

function Remove-WorkpointConfigFile {
    param (
        [Parameter(Mandatory=$true)]
        [String]
        $Path,

        [ValidateSet('Client', 'Server')]
        [String[]]
        $Type = @('Client', 'Server')
    )
    
    foreach($_ in $Type){
        $file = "$Path\WorkpointBPM$_.dll.config"

        Write-Host "removing Workpoint config file at $file"
        # only copy if the Workpoint client dll is there even if the build file says to do it.
        if (Test-Path -Path $file) {
            Write-Host "removing config files"
            Remove-Item -Path $file -Force
        }
    }
}

function Stop-IIS-AppPool {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $AppPoolName
    )
    ..\Repository.Shared\iis-webapp-stop.ps1 -AppPoolNames $AppPoolName
}

function Stop-IIS-AppPools {
    param (
        [Parameter(Mandatory=$true)]
        [string[]]
        $AppPoolNames
    )
    ..\Repository.Shared\iis-webapp-stop.ps1 -AppPoolNames $AppPoolNames
}

function Stop-IISExpress {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $Project
    )

    # have to use Get-CimInstance instead of Get-Process because that is the
    # only way to get the command line used to launch the executable
    $process = Get-CimInstance Win32_Process -Filter "name = 'iisexpress.exe'"
    foreach($proc in $process)
    {
        $cmdLine = $proc.CommandLine
        if (!$cmdLine){
            continue;
        }
        $expPid = $proc.ProcessId
        if ($cmdLine.Contains("$Project")) {
            Write-Host "stopping the IISExpress process for $Project with the PID $expPid"
            Stop-Process -Id $expPid -Force
        }
    }
}

function Config-IIS-WebApp {
    param(
        [string]$SiteName = 'Default Web Site',
        [string]$AppName,
        [string]$PhysicalPath,
        [string]$AppPoolName = '',
        [string]$LoadUserProfile = 'true',
        [string]$RuntimeVersion = 'v4.0'
    )

    # running through an external file because it requires a powershell
    # module that won't be installed on developer workstations if IIS is
    # not installed (in 2020 it should not be)
    ..\Repository.Shared\iis-webapp-setup.ps1 `
        -SiteName $SiteName `
        -AppName $AppName `
        -PhysicalPath $PhysicalPath `
        -AppPoolName $AppPoolName `
        -LoadUserProfile $LoadUserProfile `
        -RuntimeVersion $RuntimeVersion
}

function Config-IISExpress {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $Solution
    )

    $configPath = (Resolve-Path -Path "$rootPath\iisexpress.config")

    Write-Host $rootPath
    Write-Host $configPath

    # if the .vs directory does not exists want to create it and create
    # it with the hidden attribute just like VS would the first time it
    # is opened
    if (!(Test-Path -Path '.vs')) {
        $d = New-Item -Path '.vs' -Type 'Directory'
        $d.Attributes = $d.Attributes -bor 'hidden'
    }
    
    # the .vs directory can be created when Visual Studio is opened but if
    # there is no web application then the config directory will not be made
    if (!(Test-Path -Path '.vs\config')) {
        New-Item -Path '.vs\config' -Type 'Directory'
    }

    # replace the [ROOT.DIR] text and copy the output to the location visual studio expects
    (Get-Content -Path $configPath) |
        ForEach-Object {$_ -Replace '\[ROOT.DIR\]', "$rootPath"} |
        Out-File -FilePath "$rootPath\$Solution\.vs\config\applicationhost.config" -Encoding utf8 -Force
    
    # if the JetBrains Rider IDE is being used then it will default to this location for its 
    # default config of the debugger
    if (Test-Path -Path '.idea\config') {
        Copy-Item `
            -Path "$rootPath\$Solution\.vs\config\applicationhost.config" `
            -Destination "$rootPath\$Solution\.idea\config\applicationhost.config"
    }
}

function Config-IISExpress-Auth {
    param(
        [String]$SiteName,

        [ValidateSet('windows', 'oidc')]
        [String]
        $AuthType = 'windows'
    )

    $appcmd = 'C:\Program Files\IIS Express\appcmd.exe'
    $configPath = (Resolve-Path -Path ".\.vs\config\applicationhost.config")
    $siteName = 'PRS.CMS.Web.Intranet/CMS'

    # if we are using OIDC for authentication then modify the web.config
    # file for PRS.CMS.Web.Intranet
    Write-Host "the AuthType is $AuthType"
    $winAuth = 'true'
    $anonAuth = 'false'
    if ($AuthType -eq 'oidc') {
        Write-Host 'setting to use OpenID Connect for authentication'
        $winAuth = 'false'
        $anonAuth = 'true'
    }

    &$appcmd set config "$SiteName" `
        -section:system.webServer/security/authentication/anonymousAuthentication `
        /enabled:$anonAuth `
        /apphostconfig:"$configPath"

    &$appcmd set config "$SiteName" `
        -section:system.webServer/security/authentication/windowsAuthentication `
        /enabled:$winAuth `
        /apphostconfig:"$configPath"

}

function Config-IIS-Auth {
    param(
        [String]$SiteName,

        [ValidateSet('windows', 'oidc')]
        [String]
        $AuthType = 'windows'
    )

    $appcmd = $env:SystemRoot + '\system32\inetsrv\appcmd.exe'

    # if we are using OIDC for authentication then modify the web.config
    # file for PRS.CMS.Web.Intranet
    Write-Host "the AuthType is $AuthType"
    $winAuth = 'true'
    $anonAuth = 'false'
    if ($AuthType -eq 'oidc') {
        Write-Host 'setting to use OpenID Connect for authentication'
        $winAuth = 'false'
        $anonAuth = 'true'
    }

    & "$appcmd" set config "$SiteName" `
        -section:system.webServer/security/authentication/anonymousAuthentication `
        /enabled:$anonAuth

    & "$appcmd" set config "$SiteName" `
        -section:system.webServer/security/authentication/windowsAuthentication `
        /enabled:$winAuth

}

function Start-IISExpress {
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $Solution,
        
        [Parameter(Mandatory=$true)]
        [string]
        $Project,

        [Parameter(Mandatory=$false)]
        [ValidateSet('x86', 'x64')]
        [string]$Bitness = 'x64',
    
        [Parameter(Mandatory=$false)]
        [string]$LauncherPath = '',

        [Parameter(Mandatory=$false)]
        [string]$LauncherArgs = ' '
    )

    Stop-IISExpress -Project $Project
    
    $rootPath = (Resolve-Path -Path '..')
    $iisexp = 'C:\Program Files\IIS Express\iisexpress.exe'
    if ($Bitness -eq 'x86'){
        $iisexp = 'C:\Program Files (x86)\IIS Express\iisexpress.exe'
    }

    $workingDir = "$rootPath\$Solution\src\$Project"
    $arguments = "/config:$rootPath\$Solution\.vs\config\applicationhost.config /site:`"$Project`""

    # this will need to be fixed up to only have a single application per IIS Express instance because
    # of this environment variable used to startup the aspnetcore module.  With IIS 10 the AppPool needs
    # the <environmentVariables><add name="" value="" /> added for these two.
    if ($LauncherPath -ne ''){
        $Env:LAUNCHER_PATH = $LauncherPath
        $Env:LAUNCHER_ARGS = $LauncherArgs
    }

    $proc = Start-Process -FilePath $iisexp `
        -ArgumentList $arguments `
        -WorkingDirectory "$workingDir" `
        -WindowStyle Hidden `
        -PassThru 
    
    Write-Host "started IISExpress for $Project in $Solution with PID $($proc.Id)"
}

function Zip-Directory {
    param (
        [string]$Path,
        [string]$Destination
    )

    $exe = "C:\Program Files\7-Zip\7z.exe"
    
    if ($IsLinux){
        $exe = "7z"
    }
    
    exec {
        & $exe a $Destination (Join-Path -Path $Path -ChildPath '*')
    }
}

function Package-SqlFiles {
    param (
        [string]$packagePath
    )

    $destPath = (Combine-Paths -Paths $packagePath, 'CaseMaxSolutions', 'database')

    # move all of these directories - we will later go back
    # and look at files to make sure they should be kept
    $paths = @('create', 'diff-reports', 'load', 'purge', 'scramble')

    foreach ($_ in $paths) {
        $p = (Join-Path -Path '.' -ChildPath $_)
        if (Test-Path -Path $p) {
            Write-Host "copying $p directory"
            Copy-Item -Path $p -Destination $destPath -Recurse -Force
        }
    }

    $p = Combine-Paths 'upgrade', 'Workpoint'
    if (Test-Path -Path $p) {
        Copy-Item -Path $p `
            -Destination (Combine-Paths $destPath, 'upgrade', 'Workpoint') `
            -Recurse `
            -Force
    }
    
    # Excluding all of the 12.x thru 19.x from packaging because I don't need those files
    # for any environment and they just bloat the number of files that windows installer
    # needs to update.  If this value is changed make sure that seed data file 
    # database\create\cms\data\version.sql indicates a new database would be created at 
    # that version or later.
    Write-Host "getting any cms directories greater than or equal to 20.x files"
    $dirs = Get-ChildItem -Path ".\upgrade\cms" -Directory | `
        Where-Object { ($_.Name -match "^2[0-9].*") -eq $true }
    
    foreach ($dir in $dirs) {
        Write-Host "packaging up $($dir.Name)"
        Copy-Item -Path $dir.FullName -Destination "$destPath\upgrade\cms\$($dir.Name)" -Recurse -Force
    }

    # want to exclude files with a suffix of _DEV because they are only needed on build/dev 
    # machines and we don't want them getting into customer systems
    Write-Host "removing _DEV.sql files"
    Get-ChildItem -Path "$destPath\upgrade" -Recurse -File | `
        Where-Object { $_.Name.EndsWith("_DEV.sql") } | `
        Remove-Item 

    # this file should not be on disk and definitely should not make it into the package
    # directory for the installer to find
    Get-ChildItem -Path "*\License.xml" -Recurse | Remove-Item -Force
}

function Stop-Workpoint {
    ..\Repository.Shared\workpoint-stop.ps1 -RootPath $rootPath
}

function Drop-Databases {
    Invoke-Build -Task Drop -File "..\Repository.Shared\manage-databases.build.ps1"
}

function Refresh-Databases {
    param (
        [String[]]
        $Databases = (property Databases),

        [ValidateSet('full', 'quick', 'diff')]
        [String]
        $UpgradeType = 'full',

        [String]
        $SqlServerName = (property SqlServerName),
        
        [ValidateSet('Debug', 'Release')]
        [String]
        $VsConfiguration = 'Debug',
    
        [String]
        $DbInstallerPsFile = ([System.IO.Path]::Combine('..', 'Repository.Shared', 'cms-dbinstaller.ps1'))
    )

    Invoke-Build -Task Drop, Restore -File "..\Repository.Shared\manage-databases.build.ps1" `
        -SqlServerName $SqlServerName `
        -Databases $Databases 
    
    Invoke-Build -Task Upgrade -File $DbInstallerPsFile `
        -UpgradeType $UpgradeType `
        -VsConfiguration $VsConfiguration
}

function Copy-AssembliesToWorkpoint {
    param (
        [String]$WpBinPath,
        [String]$Project,
        [String]$VsBinPath
    )

    $dest = (Join-Path $WpBinPath 'cms')
    New-Directory -Path $dest

    # need to get all the DLLs from CaseMax directory because it will include assemblies
    # that are not being referenced by firm specific Scripts project
    if (Test-Path -Path "..\.external-bin\CMS\Workpoint.NET\server\bin\cms"){
        Write-Host "copying assemblies from CaseMax external-bin"
        Copy-Item -Path "..\.external-bin\CMS\Workpoint.NET\server\bin\*" -Destination $WpBinPath -Recurse -Force
    }

    Package-Directory -Project $Project -VsBinPath $VsBinPath -Destination $dest
    # don't want the workpoint dlls in the cms folder because they will already exists 
    # in the bin of the workpoint install
    Get-ChildItem -Path "$dest\*" -File -Include 'Workpoint*', 'MSEL*', 'Northwoods.GoWPF.dll' |
        Remove-Item

}

function Install-NPM {
    
    Write-Host "running npm install"
    if ($IsLinux -eq $true){
        exec {
            & npm install 
        }
    }
    else {
        exec {
            #
            # NPM will write warnings to the STDERR.  I tried to do the interception in PowerShell as suggested at
            # https://stackoverflow.com/questions/34917977/disable-npm-warnings-as-errors-build-definition-tfs
            # But NPM was still writing to the STDERR before sending the results to PowerShell so CC.NET was 
            # marking the build as failed.  
            #
            # Using --loglevel to filter out WARN from the output
            & npm install --loglevel=error
        }
    }

}

function Invoke-Webpack {
    param (
        [string]$Mode
    )

    $webpackPath = Join-Path -Path "." -ChildPath "node_modules\webpack\bin\webpack"
    exec {
        node "$webpackPath" --mode=$Mode
    }
}
function Remove-DuplicateFiles {
    param (
        [string]$Path,
        [string]$CompareToPath,
        [string]$IgnorePrefix = ''
    )
    
    # the ignore prefix can be used with Firm specific assemblies (SAPC.CMS/SIPWC.CMS).  It is important to use
    # because in order to run Workpoint those Firm specific assemblies have to be copied to CMS\Workpoint.NET\bin\cms
    # That would cause them to be picked up as duplicate assemblies when building the package directories for the
    # Firm specific files.  This does introduce a problem that will be seen when the Firm assemblies add references
    # to other DLLs.  When that happens we can switch IgnorePrefix over to an array or look for an alternate approach.

    $p1 = (Resolve-Path -Path $Path)
    $p2 = (Resolve-Path -Path $CompareToPath)

    Get-ChildItem -Path "$p1" -File -Recurse |
        ForEach-Object -Process {
            $testPath = $_.FullName.Replace($p1, $p2)

            if (Test-Path -Path $testPath){
                if (($IgnorePrefix -ne '') -and ($_.Name.StartsWith($IgnorePrefix))) {
                    Write-Host "ignoring duplicate $( $_.FullName ) because of prefix $IgnorePrefix"
                }
                else {
                    Remove-Item -Path $_.FullName
                    Write-Host "deleted duplicate $( $_.FullName )"
                }
            }
        }
}

function Setup-RegistryConnectionString {
    param (
      [Parameter(Mandatory=$false)]
      [String]
      $SqlServerName = 'localhost',
        
      [Parameter(Mandatory=$false)]
      [String]
      $DatabaseName = 'cms',
      
      [Parameter(Mandatory=$false)]
      [ValidateSet('x64', 'x86')]
      [String]
      $Bitness = 'x64'
    )

    $path = "HKLM:\SOFTWARE\CaseMaxSolutions\ConnectionStrings\$DatabaseName"
    if ($Bitness -eq 'x86'){
        $path = "HKLM:\SOFTWARE\WOW6432Node\CaseMaxSolutions\ConnectionStrings\$DatabaseName"
    }

    # only create registry key if it does not exist - creating key here requires admin permission
    if (!(Test-Path -Path $path)){
        New-Item -Path $path -Force
        New-ItemProperty -Path $path -PropertyType String -Name "Initial Catalog" -Value $DatabaseName
        New-ItemProperty -Path $path -PropertyType String -Name "Integrated Security" -Value "SSPI"
        New-ItemProperty -Path $path -PropertyType String -Name "Server" -Value $SqlServerName
    }

    # only update if it doesn't match - requires elevated permissions to update
    $val = (Get-ItemProperty -Path $path).Server
    if ($val -ne $SqlServerName){
        Set-ItemProperty -Path $path -Name "Server" -Value $SqlServerName
    }

}

function Config-ExtBinIISExpress {

    $rootPath = (Resolve-Path -Path '..')
    $configPath = (Resolve-Path -Path "$rootPath\Repository.Shared\iisexpress-extbin.config")

    Write-Host "rootPath = $rootPath"
    Write-Host "configPath = $configPath"

    # replace the [ROOT.DIR] text and copy the output to the location visual studio expects
    (Get-Content -Path $configPath) |
        ForEach-Object {$_ -Replace '\[ROOT.DIR\]', "$rootPath"} |
        Out-File -FilePath "$rootPath\.external-bin\applicationhost.config" -Encoding utf8 -Force
}

function Restart-ExtBinIISExpress {

    $rootPath = (Resolve-Path -Path '..')
    
    # this copies the iisexpress.config file from Repository.Shared 
    # and replaces ROOT.DIR with actual path
    Config-ExtBinIISExpress 

    # this makes sure these two websites have been stopped
    Stop-ExtBinIISExpress

    $cmsProc = Start-Process -FilePath 'C:\Program Files\IIS Express\iisexpress.exe' `
        -ArgumentList "/config:$rootPath\.external-bin\applicationhost.config /site:`"PRS.CMS.Web.Intranet`""`
        -WindowStyle Hidden `
        -PassThru

    $pwProc = Start-Process -FilePath 'C:\Program Files\IIS Express\iisexpress.exe' `
        -ArgumentList "/config:$rootPath\.external-bin\applicationhost.config /site:`"PRS.CMS.PaperWise.Intranet`""`
        -WindowStyle Hidden `
        -PassThru

    Write-Host "started IISExpress for PRS.CMS.Web.Intranet with PID $($cmsProc.Id) and PRS.CMS.PaperWise.Intranet with PID $($pwProc.Id)"

}

function Stop-ExtBinIISExpress {
    # this makes sure these two websites have been stopped
    Stop-IISExpress -Project 'PRS.CMS.Web.Intranet'
    Stop-IISExpress -Project 'PRS.CMS.PaperWise.Intranet'
}

function Start-AzureStorageEmulator {
    param(
        $ExePath = "..\.external-bin\AzureStorageEmulator\AzureStorageEmulator.exe",
        $SqlServerName
    )

    # https://docs.microsoft.com/en-us/azure/storage/common/storage-use-emulator
    & "$ExePath" init -server "$SqlServerName"
    & "$ExePath" start
}

function Create-AzureStorageContainer {
    param (
        [string]$ContainerName,
        [datetime]$TokenExpiresAt
    )
    
    $token = (& "$rootPath\Repository.Shared\az-container-create.ps1" -ContainerName $ContainerName -TokenExpiresAt $TokenExpiresAt)
    Write-Output $token
}

function Clean-DotNet {
    param(
        [string]$Solution,
        [string]$VsConfiguration,
        [string]$Platform = 'Any CPU'
    )

    if (Test-Path -Path '.\.build') {
        Remove-Item -Path .\.build -Recurse -Force -ErrorAction SilentlyContinue
    }

    # MSBuild will not get rid of obj files 
    Remove-CompilerFiles

    exec {
        dotnet clean "$Solution.sln" `
            --configuration $VsConfiguration 
    }
}

function Clean-Solution {
    param(
        [string]$Solution,
        [string]$VsConfiguration,
        [string]$Platform = 'Any CPU'
    )

    if (Test-Path -Path '.\.build') {
        Remove-Item -Path .\.build -Recurse -Force -ErrorAction SilentlyContinue
    }

    # MSBuild will not get rid of obj files 
    Remove-CompilerFiles

    exec {
        MSBuild "$Solution.sln" /target:Clean `
            /property:Configuration=$VsConfiguration `
            /property:Platform="$Platform" `
            /property:RestorePackages=false
    }

}

function Build-DotNet {
    param(
        [string]$Solution,
        [string]$VsConfiguration,
        [string]$Platform = 'Any CPU'
    )

    #
    # CreateDocumentationFile - using that name because it is supporting the current MSBuild, 
    # the .NET Core SDK property of GenerateDocumentationFile, and not generating Xml Doc file 
    # for tests projects.  If the tests projects was not around then we would just use the property
    # GenerateDocumenationFile and skip the conditional <PropertyGroup> in the csproj file.

    exec {
        dotnet build "$Solution.sln" `
            --configuration $VsConfiguration `
            -p:Platform="$Platform" `
            -p:CreateDocumentationFile="true" `
            -p:GeneratePackageOnBuild="true"
    }

    # This is needed because legacy MSBuild project using Analyzers are dropping files related to 
    # Code Analysis in the bin directory.  Don't want those to get packaged up. 
    Remove-CodeAnalysisOutputFiles
}

function Build-Solution {
    param(
        [string]$Solution,
        [string]$VsConfiguration,
        [string]$Platform = 'Any CPU'
    )

    Restore-NuGet -Solution "$Solution"
   
    #
    # CreateDocumentationFile - using that name because it is supporting the current MSBuild, 
    # the .NET Core SDK property of GenerateDocumentationFile, and not generating Xml Doc file 
    # for tests projects.  If the tests projects was not around then we would just use the property
    # GenerateDocumenationFile and skip the conditional <PropertyGroup> in the csproj file.
    
    exec {
        MSBuild "$Solution.sln" /target:Build `
            /property:Configuration=$VsConfiguration `
            /property:Platform="$Platform" `
            /property:CreateDocumentationFile="true" `
            /property:GeneratePackageOnBuild="true" `
            /property:CMS_BuildType="$BuildType"
    }
    
    # This is needed because legacy MSBuild project using Analyzers are dropping files related to 
    # Code Analysis in the bin directory.  Don't want those to get packaged up. 
    Remove-CodeAnalysisOutputFiles
}
