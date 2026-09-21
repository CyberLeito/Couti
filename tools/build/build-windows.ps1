# Compile the installer and WinPE helpers. Does not execute or test them.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs = & $vswhere -latest -products '*' -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$toolset = 'v143'
if (-not $vs) {
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    $toolset = 'v145'
}
if (-not $vs) { throw 'Install Visual Studio desktop C++ tools and a Windows SDK.' }
$msbuild = Join-Path $vs 'MSBuild/Current/Bin/MSBuild.exe'
$jobs = @(
    @('Ventoy2Disk/Ventoy2Disk/Ventoy2Disk.vcxproj', 'Win32', 'installer'),
    @('vtoyjump/vtoyjump/vtoyjump.vcxproj', 'Win32', 'Win32'),
    @('vtoyjump/vtoyjump/vtoyjump.vcxproj', 'x64', 'x64')
)
foreach ($job in $jobs) {
    $out = Join-Path $repo ('.build/windows/' + $job[2] + '/')
    $obj = Join-Path $repo ('.build/windows/obj/' + $job[2] + '/')
    & $msbuild (Join-Path $repo $job[0]) /nologo /m /v:minimal /clp:ErrorsOnly `
        /p:Configuration=Release "/p:Platform=$($job[1])" "/p:PlatformToolset=$toolset" `
        /p:WindowsTargetPlatformVersion=10.0 "/p:OutDir=$out" "/p:IntDir=$obj"
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $($job[0]) $($job[1])" }
}
Copy-Item -LiteralPath (Join-Path $repo '.build/windows/Win32/vtoyjump32.exe') -Destination (Join-Path $repo 'INSTALL/ventoy/vtoyjump32.exe')
Copy-Item -LiteralPath (Join-Path $repo '.build/windows/x64/vtoyjump64.exe') -Destination (Join-Path $repo 'INSTALL/ventoy/vtoyjump64.exe')
& (Join-Path $PSScriptRoot 'build-installer.ps1')
Write-Output 'Couti Windows executables compiled. No tests run.'
