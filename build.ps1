$ErrorActionPreference = "Stop";

New-Item  -Path ./.nuget -ItemType Directory -Force

dotnet tool restore

Push-Location ./src
Invoke-Expression "./build.ps1 $args"
Pop-Location
