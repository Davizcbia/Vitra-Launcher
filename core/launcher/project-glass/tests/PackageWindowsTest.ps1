$ErrorActionPreference = 'Stop'
$source = (Resolve-Path "$PSScriptRoot\..\..\..\..\package_windows.ps1").Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) ("vitra-package-test-" + [guid]::NewGuid().ToString('N'))
New-Item "$fixture\core\build-win11\Release", "$fixture\core\build-win11\buildconfig", "$fixture\dist" -ItemType Directory -Force | Out-Null
Copy-Item -LiteralPath $source -Destination "$fixture\package_windows.ps1"
@'
set(Launcher_VERSION_MAJOR 0)
set(Launcher_VERSION_MINOR 0)
set(Launcher_VERSION_PATCH 1)
'@ | Set-Content "$fixture\core\CMakeLists.txt"
'https://github.com/Davizcbia/Vitra-Launcher FLAME_API_KEY = "fixture"' | Set-Content "$fixture\core\build-win11\buildconfig\BuildConfig.cpp"
'fixture launcher' | Set-Content "$fixture\core\build-win11\Release\VitraLauncher.exe"
'fixture updater' | Set-Content "$fixture\core\build-win11\Release\VitraLauncher_updater.exe"
$name = 'VitraLauncher-Windows-MSVC-Portable-0.0.1'
New-Item "$fixture\dist\$name\instances" -ItemType Directory -Force | Out-Null
'user save' | Set-Content "$fixture\dist\$name\instances\save.txt"
'old archive' | Set-Content "$fixture\dist\$name.zip"
$oldRepository = $env:PG_UPDATER_REPO
try {
    $env:PG_UPDATER_REPO = 'https://github.com/Davizcbia/Vitra-Launcher'
    & "$fixture\package_windows.ps1" -NoBuild
    if ((Get-Content "$fixture\dist\$name\instances\save.txt" -Raw).Trim() -ne 'user save') { throw 'Existing user data changed.' }
    $previous = @(Get-ChildItem "$fixture\dist\$name.zip.previous-*")
    if ($previous.Count -ne 1 -or (Get-Content $previous[0].FullName -Raw).Trim() -ne 'old archive') { throw 'Previous archive was not preserved.' }
    $zip = [IO.Compression.ZipFile]::OpenRead("$fixture\dist\$name.zip")
    try {
        $entries = @($zip.Entries | ForEach-Object FullName)
        if ('portable.txt' -notin $entries -or 'manifest.txt' -notin $entries -or 'VitraLauncher.exe' -notin $entries) { throw 'Required files missing.' }
        if (@($entries | Where-Object { $_ -like 'instances/*' }).Count) { throw 'User data entered the package.' }
    } finally { $zip.Dispose() }
    $before = (Get-FileHash "$fixture\dist\$name.zip").Hash
    $locked = [IO.File]::Open("$fixture\core\build-win11\Release\VitraLauncher.exe", 'Open', 'ReadWrite', 'None')
    $failed = $false
    try { & "$fixture\package_windows.ps1" -NoBuild } catch { $failed = $true } finally { $locked.Dispose() }
    if (-not $failed) { throw 'Expected the locked source to fail packaging.' }
    if ((Get-FileHash "$fixture\dist\$name.zip").Hash -ne $before) { throw 'Failed packaging replaced the published archive.' }
    if (-not (Test-Path "$fixture\dist\$name\instances\save.txt")) { throw 'Failed packaging removed user data.' }
    Write-Host 'PackageWindowsTest passed: user data, previous archive, contents and failed publication.'
} finally {
    $env:PG_UPDATER_REPO = $oldRepository
    $resolved = [IO.Path]::GetFullPath($fixture)
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolved).StartsWith('vitra-package-test-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
