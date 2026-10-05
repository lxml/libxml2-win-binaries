<#
This script builds libiconv, zlib, libxml2 and libxslt
#>
Param(
    [switch]$x64,
    [switch]$arm64
)

$ErrorActionPreference = "Stop"
Import-Module Pscx

Function Get-BatPath($vcvarsarch) {
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
            $vcvars = (Get-ChildItem $buildDir -Filter "vcvars*$vcvarsarch*.bat" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
            Write-Host "Tried $buildDir, found $vcvars"
            if (-not $vcvars) { continue }

            Write-Host "Using: $vcvars"
            return "$vcvars"
        }
    }

    throw "vcvars*.bat not found"
}

$platDir = If($x64) { "\x64" } ElseIf ($arm64) { "\arm64" } Else { "\Win32" }
$distname = If($x64) { "win64" } ElseIf($arm64) { "win-arm64" } Else { "win32" }

$vcvarsarch = If($x64) { "x86_amd64" } ElseIf ($arm64) { "arm64" } Else { "32" }

$bat = Get-BatPath $vcvarsarch

& cmd.exe /c "`"$bat`" && set" | ForEach-Object {
    if ($_ -match "^([^=]+)=(.*)$") {
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
    }
}

Set-Location $PSScriptRoot

Set-Location .\libiconv\MSVC17
if ($arm64) {
    (Get-Content -Path "libiconv_dll\libiconv_dll.vcxproj") -replace ">10.0.19041.0<", ">10.0.22621.0<" | Set-Content -Path "libiconv_dll\libiconv_dll.vcxproj"
    (Get-Content -Path "libiconv_static\libiconv_static.vcxproj") -replace ">10.0.19041.0<", ">10.0.22621.0<" | Set-Content -Path "libiconv_static\libiconv_static.vcxproj"
}
msbuild libiconv_static\libiconv_static.vcxproj /p:Configuration=Release
$iconvLib = Join-Path (pwd) $platDir\lib

$iconvInc = Join-Path $PSScriptRoot libiconv\source\include

Set-Location $PSScriptRoot

Set-Location .\zlib
Start-Process -NoNewWindow -Wait nmake "-f win32/Makefile.msc zlib_a.lib"
$zlibLib = (pwd)
$zlibInc = (pwd)

Move-Item zlib_a.lib zlib.lib -force

Set-Location ..

Set-Location .\libxml2\win32
cscript configure.js lib="$zlibLib;$iconvLib" include="$zlibInc;$iconvInc" vcmanifest=yes zlib=yes
Start-Process -NoNewWindow -Wait nmake libxmla
$xmlLib = Join-Path (pwd) bin.msvc
$xmlInc = Join-Path (pwd) ..\include
Set-Location ..\..

Set-Location .\libxslt\win32
cscript configure.js lib="$zlibLib;$iconvLib;$xmlLib" include="$zlibInc;$iconvInc;$xmlInc" vcmanifest=yes zlib=yes
Start-Process -NoNewWindow -Wait nmake "libxslta libexslta"
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
BundleRelease "zlib-1.3.2.$distname" (Get-Item .\zlib\*.*) (Get-Item .\zlib\zconf.h,.\zlib\zlib.h)
