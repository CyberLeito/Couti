# Compile the English x86 frontend and embed its storage service. Never launches it.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'
if (!(Test-Path -LiteralPath $compiler)) { throw '.NET Framework 4.x compiler is required.' }
& $compiler /nologo /target:winexe /platform:x86 /optimize+ /codepage:65001 `
    /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll `
    "/win32icon:$(Join-Path $repo 'ICON/Couti_icon.ico')" "/win32manifest:$(Join-Path $repo 'CoutiInstaller/app.manifest')" `
    "/resource:$(Join-Path $repo 'CoutiInstaller/Couti.Storage.ps1'),Couti.Storage.ps1" `
    "/out:$(Join-Path $repo 'INSTALL/Couti2Disk.exe')" (Join-Path $repo 'CoutiInstaller/CoutiInstaller.cs')
if ($LASTEXITCODE -ne 0) { throw 'Couti Installer compilation failed.' }
Write-Output 'Couti Installer x86 compiled. No execution or tests performed.'
