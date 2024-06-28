<#
.SYNOPSIS
Bootstrap file for calling Invoke-Build using the file .\.build.ps1

.PARAMETER Solution
The name of the Solution to build.  If no value is supplied then all (except for 'dev' builds) the solutions are 
processed.

The default value is empty and all Solutions are processed.

.PARAMETER Task
An array of task to ask the build file to perform.  The following Tasks are supported:
  * DependenciesUpdate : Updates .external-bin directory
  * Build-All : typically run by build server to do an everything build
  * Build-Package : typically run on dev workstation to switch over to this branch
  * Clean : removes all build output
  * Build : compiles the solutions
  * Setup : sets up applications required to run solutions (such as IIS, IIS Express, Workpoint)
  * Test : runs the automated tests in the solutions
  * Package : packages the content of the build
  * UpdateAssemblyInfo : updates all AssemblyCommonInfo.cs files

The tasks Build-All, Build-Package, Clean, Build, Setup, Test, and Package will iterate through the Solutions or 
the specific Solution parameter.  All other tasks should be assumed to run one-time and not be specific to a
Solution.

.PARAMETER BuildType
The type of build to perform.  'dev' or 'beta' are typically performed on developer workstations.
'ccnet', 'nightly', or 'rc' are typically performed on build server.

.EXAMPLE
.\build.ps1 -Task Build-Package

This is the command to run when switching over to this branch on a developer workstation.  It will
get rid of any old VS output for each solution, then run Build and Setup and Test for every solution, 
then Refresh the databases.

.EXAMPLE
.\build.ps1 -Solution IdentityServer4 -Task Build

This is the command to run for building a specific solution.

.EXAMPLE
.\build.ps1 -Solution IdentityServer4 -Task Test

This is the command to run for running the tests in a specific solution.

.EXAMPLE
.\build.ps1 -Task Build-All -BuildType 'ccnet'

This is the command to run on a build server to perform a ccnet build.  

#>
param(

    [Parameter(Mandatory=$false)]
    [String]
    $Solution = '',

    [Parameter(Mandatory=$false)]
    [ValidateSet('DependenciesUpdate', 'Build-All', 'Build-Package', 'Clean', 'Build', 'Setup', 'Test', 'Package', 'UpdateAssemblyInfo')]
    [String[]]
    $Task = 'Build-Package',

    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'ccnet', 'nightly', 'beta', 'rc')]
    [String]
    $BuildType = 'dev'
)

# need to make sure PowerShell is using latest security protocol on older OS versions
# to make http requests. The old SSL3 will fail on most https based connections - such 
# as the one to https://aka.ms
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$invokeBuildVersion = '5.11.2'
Write-Host "checking to see if InvokeBuild $invokeBuildVersion module is installed"
if (!(Get-Module -Name 'InvokeBuild' -ListAvailable | Where-Object {$_.Version -eq $invokeBuildVersion})) {
    Write-Host "installing InvokeBuild $invokeBuildVersion module"
    Install-Module -Name 'InvokeBuild' -RequiredVersion $invokeBuildVersion -Scope CurrentUser -Confirm:$false -Force
}

Import-Module -Name InvokeBuild -RequiredVersion $invokeBuildVersion

$started = Get-Date

$solutions = @(
    'IdentityServer4'
)

# Create this directory so the NuGet.config does not cause issues with a source directory
# it references being missing.  Otherwise it would not get created until 
# (the first solution) performed a build.  But to do the build it needs to use NuGet to 
# get the external dependencies downloaded
if (!(Test-Path -Path '.\.build\packages')) {
    New-Item .\.build\packages -ItemType Directory
}

Invoke-Build -Task $Task `
    -File '.\Repository.Shared\root.build.ps1' `
    -ProductName 'IdentityServer4' `
    -Solutions $solutions `
    -BuildType $BuildType

$ended = Get-Date

if ($BuildType -eq 'dev') {
    Write-Host "Started At: $started and Ended At: $ended"
}
