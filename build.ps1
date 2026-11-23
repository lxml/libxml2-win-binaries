<#
This script builds libiconv, zlib, libxml2 and libxslt
#>
Param(
    [switch]$x64,
    [switch]$arm64,
    [ValidateSet("14.44", "14.52")]
    [string]$toolset
)

$ErrorActionPreference = "Stop"
Import-Module Pscx

Function Get-BatPath($vcvarsarch, $toolset) {
    $editions = "Community", "Enterprise"
    $years = 2022, 18

    foreach ($year in $years) {
        if (Test-Path "C:\Program Files\Microsoft Visual Studio\$year\") {
            $basedir = "C:\Program Files\Microsoft Visual Studio\$year\"
        } elseif (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio\$year\") {
            $basedir = "C:\Program Files (x86)\Microsoft Visual Studio\$year\"
        } else {
            continue
        }

        foreach ($edition in $editions) {
            $buildDir = "$basedir$edition\VC\Auxiliary\Build\"
            $msvcDir = "$basedir$edition\VC\Tools\MSVC"
            $vcvars = (Get-ChildItem $buildDir -Filter "vcvars$vcvarsarch.bat" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName

            Write-Host "Tried $buildDir, found $vcvars"
            if (-not $vcvars) { continue }

            $msvcVersions = Get-ChildItem $msvcDir -Directory | Where-Object { $_.Name -like "$toolset.*" }
            if (-not $msvcVersions) { continue }
            $paths = $msvcVersions.FullName
            Write-Host "Found $paths"

            $selectedVersion = ($msvcVersions | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1).Name
            Write-Host "Using: $vcvars for MSVC $selectedVersion"
            return $vcvars, $selectedVersion
        }
    }

    throw "MSVC $toolset for $vcvarsarch is required; install it with the Visual Studio Installer."
}

$platDir = If($x64) { "\x64" } ElseIf ($arm64) { "\arm64" } Else { "\Win32" }
$distname = If($x64) { "win64" } ElseIf($arm64) { "win-arm64" } Else { "win32" }

$vcvarsarch = If($x64) { "x86_amd64" } ElseIf ($arm64) { "arm64" } Else { "32" }

# Keep these toolset families in sync with lxml/buildlibxml.py.
if (-not $toolset) { $toolset = If ($arm64) { "14.52" } Else { "14.44" } }
$bat, $selectedVersion = Get-BatPath $vcvarsarch $toolset

& cmd.exe /d /c "`"$bat`" -vcvars_ver=$selectedVersion && set" | ForEach-Object {
    if ($_ -match "^([^=]+)=(.*)$") {
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
    }
}

if ($LASTEXITCODE -ne 0) { throw "vcvars failed: $LASTEXITCODE" }
if ($env:VCToolsVersion.TrimEnd('\', '/') -ne $selectedVersion) {
    throw "Visual Studio did not select MSVC $selectedVersion"
}

# /GL objects require the exact compiler version, including servicing patches.
$probe = [IO.Path]::GetTempFileName()
try {
    Set-Content -Path $probe -Value "_MSC_FULL_VER" -Encoding ascii
    $compilerVersion = (& cl.exe /nologo /EP /TC $probe | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $compilerVersion -notmatch '^\d+$') {
        throw "Cannot determine _MSC_FULL_VER: $compilerVersion"
    }
} finally {
    Remove-Item $probe
}
$distname = "$distname.msvc-$compilerVersion"
Write-Host "_MSC_FULL_VER: $compilerVersion"
Write-Host "VCToolsVersion: $env:VCToolsVersion"
Write-Host "MSVC_VER: $env:MSVC_VER"
Write-Host "VisualStudioVersion: $env:VisualStudioVersion"

Set-Location $PSScriptRoot

$msvcConfigDir = If ($arm64) { "MSVC18" } Else { "MSVC17" }
Set-Location .\libiconv\$msvcConfigDir
$platform = If ($x64) { "x64" } ElseIf ($arm64) { "ARM64" } Else { "Win32" }
$platformToolset = If ($toolset -eq "14.44") { "v143" } Else { "v145" }
msbuild libiconv_static\libiconv_static.vcxproj /p:Configuration=Release /p:Platform=$platform /p:PlatformToolset=$platformToolset /p:VCToolsVersion=$selectedVersion
if ($LASTEXITCODE -ne 0) { throw "libiconv build failed: $LASTEXITCODE" }
$iconvLib = Join-Path (pwd) $platDir\lib

$iconvInc = Join-Path $PSScriptRoot libiconv\source\include

Set-Location $PSScriptRoot

Set-Location .\zlib
$build = Start-Process -NoNewWindow -Wait -PassThru nmake "-f win32/Makefile.msc zlib_a.lib"
if ($build.ExitCode -ne 0) { throw "zlib build failed: $($build.ExitCode)" }
$zlibLib = (pwd)
$zlibInc = (pwd)

Move-Item zlib_a.lib zlib.lib -force

Set-Location ..

Set-Location .\libxml2\win32
cscript configure.js lib="$zlibLib;$iconvLib" include="$zlibInc;$iconvInc" vcmanifest=yes zlib=yes
$build = Start-Process -NoNewWindow -Wait -PassThru nmake libxmla
if ($build.ExitCode -ne 0) { throw "libxml2 build failed: $($build.ExitCode)" }
$xmlLib = Join-Path (pwd) bin.msvc
$xmlInc = Join-Path (pwd) ..\include
Set-Location ..\..

Set-Location .\libxslt\win32
cscript configure.js lib="$zlibLib;$iconvLib;$xmlLib" include="$zlibInc;$iconvInc;$xmlInc" vcmanifest=yes zlib=yes
$build = Start-Process -NoNewWindow -Wait -PassThru nmake "libxslta libexslta"
if ($build.ExitCode -ne 0) { throw "libxslt build failed: $($build.ExitCode)" }
Set-Location ..\..

# Bundle releases
Function BundleRelease($name, $lib, $inc)
{
    New-Item -ItemType Directory .\dist\$name

    New-Item -ItemType Directory .\dist\$name\lib
    Copy-Item -Recurse $lib .\dist\$name\lib
    Get-ChildItem -File -Recurse .\dist\$name\lib | Where{$_.Name -NotMatch ".(lib|pdb)$" } | Remove-Item

    New-Item -ItemType Directory .\dist\$name\include
    Copy-Item -Recurse $inc .\dist\$name\include
    Get-ChildItem -File -Recurse .\dist\$name\include | Where{$_.Name -NotMatch ".h$" } | Remove-Item

    Write-Zip  .\dist\$name .\dist\$name.zip
    Remove-Item -Recurse -Path .\dist\$name
}

if (Test-Path .\dist) { Remove-Item .\dist -Recurse }
New-Item -ItemType Directory .\dist

# lxml expects iconv to be called iconv, not libiconv
Dir $iconvLib\libiconv* | Copy-Item -Force -Destination {Join-Path $iconvLib ($_.Name -replace "libiconv","iconv") }

BundleRelease "iconv-1.19.$distname" (dir $iconvLib\iconv_a*) (dir $iconvInc\*)
BundleRelease "libxml2-2.11.9.$distname" (dir $xmlLib\*) (Get-Item $xmlInc\libxml)
BundleRelease "libxslt-1.1.45.$distname" (dir .\libxslt\win32\bin.msvc\*) (Get-Item .\libxslt\libxslt,.\libxslt\libexslt)
BundleRelease "zlib-1.4.$distname" (Get-Item .\zlib\*.*) (Get-Item .\zlib\zconf.h,.\zlib\zlib.h)
