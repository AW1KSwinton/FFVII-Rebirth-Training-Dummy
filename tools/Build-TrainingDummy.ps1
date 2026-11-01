[CmdletBinding(SupportsShouldProcess)]
param(
    # Build: clone the rows and pack TrainingDummy_P. Install/Uninstall: copy
    # the pak triplet and the UE4SS mod into, or out of, the game.
    [ValidateSet('Build', 'Install', 'Uninstall', 'Status')]
    [string]$Mode = 'Build',
    # Machine paths, JSON (default tools\build-config.local.json).
    [string]$ConfigPath = $null,
    # Diagnostics: build only the listed tables (e.g. 'EnemyTerritory','BattleCharaSpec').
    [string[]]$OnlyTables = @(),
    # Diagnostics: build from another spec file.
    [string]$SpecPath = $null
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$ModRoot = Split-Path $PSScriptRoot -Parent
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'build-config.local.json' }
# Machine paths come from build-config.local.json (copy build-config.example.json).
$Config = [ordered]@{
    GameRoot      = $null  # FF7 Rebirth install folder
    VanillaRoot   = $null  # FModel raw export root containing End\Content\DataObject\Resident
    UnrealReZen   = $null  # UnrealReZen.exe
    BuildRoot     = (Join-Path $ModRoot 'build')
    BackupRoot    = (Join-Path $ModRoot 'build\backups')
}
if (Test-Path -LiteralPath $ConfigPath) {
    $local = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    foreach ($p in $local.PSObject.Properties) { $Config[$p.Name] = $p.Value }
}
foreach ($key in 'GameRoot', 'VanillaRoot', 'UnrealReZen') {
    if (-not $Config[$key]) { throw "Set $key in $ConfigPath (see build-config.example.json)." }
}

$PackageName = 'TrainingDummy_P'
$Spec = if ($SpecPath) { $SpecPath } else { Join-Path $ModRoot 'data\training-dummy.json' }
$BuilderProject = Join-Path $PSScriptRoot 'DataBuilder\DataBuilder.csproj'
$Builder = Join-Path $PSScriptRoot 'DataBuilder\bin\Release\net8.0\TrainingDummy.DataBuilder.dll'
$Paks = Join-Path $Config.GameRoot 'End\Content\Paks'
$ModsDir = Join-Path $Paks '~mods'
$Ue4ssMods = Join-Path $Config.GameRoot 'End\Binaries\Win64\ue4ss\Mods'
$RuntimeSource = Join-Path $ModRoot 'ue4ss\TrainingDummy'
# IoStore containers written by UnrealReZen need the game's 10-byte UCAS
# header before Rebirth will mount them.
$HeaderSource = Join-Path $Paks 'pakchunk4optional-WindowsNoEditor.ucas'
$ExpectedHeader = [byte[]](0x8C, 0x06, 0x00, 0x97, 0xA6, 0x88, 0x97, 0xA4, 0xD3, 0x00)

function Get-Triplet([string]$Directory) {
    '.pak', '.ucas', '.utoc' | ForEach-Object { Join-Path $Directory ($PackageName + $_) }
}

function Read-Header([string]$Path) {
    $bytes = New-Object byte[] 10
    $stream = [IO.File]::OpenRead($Path)
    try { if ($stream.Read($bytes, 0, 10) -ne 10) { throw "Too short for a UCAS header: $Path" } }
    finally { $stream.Dispose() }
    , $bytes
}

function Set-RebirthHeader([string]$Path) {
    $source = Read-Header $HeaderSource
    if ([BitConverter]::ToString($source) -ne [BitConverter]::ToString($ExpectedHeader)) {
        throw "The game's $HeaderSource no longer has the known Rebirth UCAS header."
    }
    $stream = [IO.File]::Open($Path, 'Open', 'Write', 'None')
    try { $stream.Write($source, 0, 10) } finally { $stream.Dispose() }
    if ([BitConverter]::ToString((Read-Header $Path)) -ne [BitConverter]::ToString($ExpectedHeader)) {
        throw "Header patch did not apply to $Path"
    }
}

function Get-HashRecord([string]$Path) {
    [ordered]@{ Name = Split-Path $Path -Leaf; Length = (Get-Item -LiteralPath $Path).Length
        SHA256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
}

function Invoke-Build {
    $staging = Join-Path $Config.BuildRoot 'Staging'
    $output = Join-Path $Config.BuildRoot 'Package'
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    New-Item -ItemType Directory -Path $staging, $output -Force | Out-Null

    & dotnet build $BuilderProject -c Release --nologo -v quiet
    if ($LASTEXITCODE -ne 0) { throw "DataBuilder build failed ($LASTEXITCODE)" }
    $buildSpec = $Spec
    if ($OnlyTables.Count -gt 0) {
        $json = Get-Content -LiteralPath $Spec -Raw
        $json = ($json -split "`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
        $parsed = $json | ConvertFrom-Json
        $parsed.tables = @($parsed.tables | Where-Object { $OnlyTables -contains [IO.Path]::GetFileNameWithoutExtension($_.asset) })
        $buildSpec = Join-Path $Config.BuildRoot 'spec.partial.json'
        $parsed | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $buildSpec -Encoding utf8
        Write-Host "Partial build: $($OnlyTables -join ', ')"
    }
    & dotnet $Builder build $buildSpec $Config.VanillaRoot $staging
    if ($LASTEXITCODE -ne 0) { throw "DataBuilder failed ($LASTEXITCODE); nothing was packed" }

    foreach ($path in Get-Triplet $output) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path } }
    # UnrealReZen must run from its own folder so it finds its Oodle DLL.
    Push-Location (Split-Path $Config.UnrealReZen -Parent)
    try {
        & $Config.UnrealReZen --content-path $staging --compression-format Zlib --engine-version GAME_UE4_26 `
            --game-dir $Paks --output-path (Join-Path $output "$PackageName.utoc")
        if ($LASTEXITCODE -ne 0) { throw "UnrealReZen failed ($LASTEXITCODE)" }
    } finally { Pop-Location }
    foreach ($path in Get-Triplet $output) {
        if (-not (Test-Path -LiteralPath $path)) { throw "UnrealReZen did not write $path" }
    }
    Set-RebirthHeader (Join-Path $output "$PackageName.ucas")

    $manifest = [ordered]@{
        PackageName = $PackageName
        BuiltAt = (Get-Date).ToString('o')
        Spec = [ordered]@{ Path = $Spec; SHA256 = (Get-FileHash -LiteralPath $Spec -Algorithm SHA256).Hash }
        Assets = @(Get-ChildItem -LiteralPath $staging -Recurse -File | ForEach-Object {
            [ordered]@{ Path = $_.FullName.Substring($staging.Length + 1); SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } })
        Files = @(Get-Triplet $output | ForEach-Object { Get-HashRecord $_ })
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'manifest.json') -Encoding utf8
    Write-Host "Built $PackageName in $output"
}

function Backup-Installed([string]$Label) {
    $existing = @(Get-Triplet $ModsDir | Where-Object { Test-Path -LiteralPath $_ })
    $runtime = Join-Path $Ue4ssMods 'TrainingDummy'
    if ($existing.Count -eq 0 -and -not (Test-Path -LiteralPath $runtime)) { return $null }
    $dest = Join-Path $Config.BackupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + "-$Label")
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    foreach ($path in $existing) { Copy-Item -LiteralPath $path -Destination $dest }
    if (Test-Path -LiteralPath $runtime) { Copy-Item -LiteralPath $runtime -Destination $dest -Recurse }
    $dest
}

function Set-ModsTxtEntry([bool]$Enabled) {
    $modsTxt = Join-Path $Ue4ssMods 'mods.txt'
    $lines = @(Get-Content -LiteralPath $modsTxt)
    $lines = @($lines | Where-Object { $_ -notmatch '^\s*TrainingDummy\s*:' })
    if ($Enabled) {
        # Keep the built-in Keybinds line last, as UE4SS expects.
        $at = [Array]::FindIndex([string[]]$lines, [Predicate[string]]{ param($l) $l -match '^\s*Keybinds\s*:' })
        if ($at -lt 0) { $lines += 'TrainingDummy : 1' }
        else { $lines = @($lines[0..($at - 1)]) + 'TrainingDummy : 1' + @($lines[$at..($lines.Count - 1)]) }
    }
    Copy-Item -LiteralPath $modsTxt -Destination "$modsTxt.backup-TrainingDummy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Set-Content -LiteralPath $modsTxt -Value $lines -Encoding ascii
}

function Invoke-Install {
    if (Get-Process -Name 'ff7rebirth_' -ErrorAction SilentlyContinue) { throw 'Close the game before installing.' }
    $package = Join-Path $Config.BuildRoot 'Package'
    $manifest = Get-Content -LiteralPath (Join-Path $package 'manifest.json') -Raw | ConvertFrom-Json
    foreach ($file in $manifest.Files) {
        $hash = (Get-FileHash -LiteralPath (Join-Path $package $file.Name) -Algorithm SHA256).Hash
        if ($hash -ne $file.SHA256) { throw "Built $($file.Name) does not match its manifest" }
    }
    $backup = Backup-Installed 'before-install'
    if ($PSCmdlet.ShouldProcess($ModsDir, "Install $PackageName and the TrainingDummy UE4SS mod")) {
        New-Item -ItemType Directory -Path $ModsDir -Force | Out-Null
        foreach ($path in Get-Triplet $package) { Copy-Item -LiteralPath $path -Destination $ModsDir -Force }
        foreach ($file in $manifest.Files) {
            $hash = (Get-FileHash -LiteralPath (Join-Path $ModsDir $file.Name) -Algorithm SHA256).Hash
            if ($hash -ne $file.SHA256) { throw "Installed $($file.Name) does not match the build" }
        }
        $runtime = Join-Path $Ue4ssMods 'TrainingDummy'
        if (Test-Path -LiteralPath $runtime) { Remove-Item -LiteralPath $runtime -Recurse -Force }
        Copy-Item -LiteralPath $RuntimeSource -Destination $runtime -Recurse
        Set-ModsTxtEntry $true
        Write-Host "Installed. Previous files backed up to: $backup"
    }
}

function Invoke-Uninstall {
    if (Get-Process -Name 'ff7rebirth_' -ErrorAction SilentlyContinue) { throw 'Close the game before uninstalling.' }
    $backup = Backup-Installed 'before-uninstall'
    if ($PSCmdlet.ShouldProcess($ModsDir, "Remove $PackageName and the TrainingDummy UE4SS mod")) {
        foreach ($path in Get-Triplet $ModsDir) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path } }
        $runtime = Join-Path $Ue4ssMods 'TrainingDummy'
        if (Test-Path -LiteralPath $runtime) { Remove-Item -LiteralPath $runtime -Recurse -Force }
        Set-ModsTxtEntry $false
        Write-Host "Uninstalled. Backup: $backup"
    }
}

function Show-Status {
    foreach ($path in Get-Triplet $ModsDir) {
        if (Test-Path -LiteralPath $path) { Get-HashRecord $path | ConvertTo-Json -Compress } else { "missing: $path" }
    }
    $runtime = Join-Path $Ue4ssMods 'TrainingDummy\Scripts\main.lua'
    if (Test-Path -LiteralPath $runtime) { "runtime: " + (Get-FileHash -LiteralPath $runtime -Algorithm SHA256).Hash } else { 'runtime: missing' }
    Select-String -LiteralPath (Join-Path $Ue4ssMods 'mods.txt') -Pattern '^\s*TrainingDummy' | ForEach-Object { "mods.txt: $($_.Line)" }
}

switch ($Mode) {
    'Build' { Invoke-Build }
    'Install' { Invoke-Install }
    'Uninstall' { Invoke-Uninstall }
    'Status' { Show-Status }
}
