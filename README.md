# libxml2 Windows binaries for lxml

[![Build status](https://ci.appveyor.com/api/projects/status/cc6q3nrosjul2sgl?svg=true)](https://ci.appveyor.com/project/mhils/libxml2-win-binaries)

This repository builds static libiconv, zlib, libxml2, and libxslt libraries for lxml on Windows with Visual Studio.

## Instructions

- Install the [Visual C++ Build Tools](http://landinghub.visualstudio.com/visual-cpp-build-tools) (or Visual Studio).
- Open a Powershell prompt and install the Powershell Community Tools: 
```powershell
Set-ExecutionPolicy remotesigned
Find-Package pscx | ? ProviderName -eq PSModule | Install-Package -Force
```
- Run `build.ps1` for x86, `build.ps1 -x64` for x64, or `build.ps1 -arm64` for ARM64.
- Take binaries from `dist/`

## Compiler compatibility

The libraries retain whole-program optimisation (`/GL` / LTCG). Both this
repository and lxml select MSVC 14.44 for x86/x64 and 14.52 for ARM64. The
required toolset must already be installed; builds fail instead of silently
selecting a different toolset. Keep the defaults in `build.ps1`, the workflow
matrix, and lxml's `buildlibxml.py` in sync when changing toolset families.

`build.ps1` passes the selected `VCToolsVersion` to both vcvars and MSBuild.
Every ZIP and its top-level directory include the compiler's `_MSC_FULL_VER`,
for example `iconv-1.19.win-arm64.msvc-195237025.zip`. lxml only consumes
archives for its exact compiler version, including servicing patches, and
uses that identity in its dependency cache keys.

Publish a new binary release after this change, before using the coordinated
lxml build. After a runner compiler update, rebuild and publish the libraries
with that compiler before lxml can consume them. An older compiler's archives
are deliberately rejected even when the library versions are unchanged.

## Acknowledgements

This work was made possible by https://github.com/winlibs!
