# Builds the Windows MSI from the local build tree, mirroring
# deploy\build_windows.bat (stage -> CPack WiX v4), minus code signing.
# Prereqs: client + service built in build_local, client\3rd-prebuilt
# populated, WiX 4 dotnet tool with WixToolset.Util.wixext, and a
# CMake >= 3.30 cpack (WiX v4 support).
# QT_BIN: Qt's bin directory (else taken from windeployqt on PATH);
# CPACK: that cpack.exe (else cpack on PATH).
$ErrorActionPreference = 'Stop'

$src   = $PSScriptRoot
$build = "$src\build_local"
$stage = "$build\stage"
$qtBin = if ($env:QT_BIN) { $env:QT_BIN } else { Split-Path (Get-Command windeployqt.exe).Source }
$cpack = if ($env:CPACK) { $env:CPACK } else { (Get-Command cpack.exe).Source }
$env:PATH = "$qtBin;$env:USERPROFILE\.dotnet\tools;$env:PATH"

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory $stage | Out-Null

Copy-Item "$build\client\Lodestar.exe" $stage
Copy-Item "$build\service\server\lodestar-service.exe" $stage
Copy-Item "$src\client\images\app.ico" "$stage\Lodestar.ico"

& "$qtBin\windeployqt.exe" --release --qmldir "$src\client" --force --no-translations "$stage\Lodestar.exe" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "windeployqt (client) failed" }
& "$qtBin\windeployqt.exe" --release "$stage\lodestar-service.exe" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "windeployqt (service) failed" }

# the client links OpenSSL 4 dynamically (local build, see client\cmake\3rdparty.cmake)
Copy-Item "$build\client\libcrypto-4-x64.dll", "$build\client\libssl-4-x64.dll" $stage

# MSVC runtime app-local, so both exes start on machines without the VC++ redist
$crt = Get-ChildItem 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Redist\MSVC\14.*\x64\Microsoft.VC143.CRT' -Directory |
    Sort-Object FullName | Select-Object -Last 1
Copy-Item "$($crt.FullName)\*.dll" $stage

Copy-Item "$src\deploy\data\windows\x64\*" $stage -Recurse -Force
Copy-Item "$src\client\3rd-prebuilt\deploy-prebuilt\windows\x64\*" $stage -Recurse -Force

Push-Location $build
try {
    Remove-Item '_CPack_Packages' -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Filter '*.msi' | Remove-Item -Force
    # only the stage dir goes into the MSI, not subprojects' install rules
    & $cpack -G WIX -C RelWithDebInfo --config "$build\CPackConfig.cmake" -D CPACK_INSTALL_CMAKE_PROJECTS=
    if ($LASTEXITCODE -ne 0) { throw "cpack failed" }
} finally {
    Pop-Location
}
Get-ChildItem $build -Filter '*.msi' | Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } }
