<#
.SYNOPSIS
  按 build.config.json 逐个打包 mod，产出可「导入 zip」的发布包。

.DESCRIPTION
  每个 mod 产出 dist/<id>-<version>.zip，zip 根目录包含：
    mod.json            —— 清单（安装器据此确定 id 与 pck 名）
    <id>.pck            —— 资源包
    icon.png            —— 可选，MOD 管理页图标
    <bundle 里的目录>   —— 可选，如 etn_coop_easytier 的 tools/<平台>/

.EXAMPLE
  .\build.ps1 -Godot "D:\Godot Engine\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe"
  .\build.ps1 -Godot $env:GODOT_BIN -Only etn_trainer
#>
param(
    [string]$Godot = $env:GODOT_BIN,
    [string]$OutputDir = "dist",
    [string[]]$Only
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$root = $PSScriptRoot
$configPath = Join-Path $root "build.config.json"
if (-not (Test-Path -LiteralPath $configPath)) { throw "找不到 build.config.json：$configPath" }
$config = [IO.File]::ReadAllText($configPath, [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
$out = Join-Path $root $OutputDir
New-Item -ItemType Directory -Path $out -Force | Out-Null

$built = @()
foreach ($entry in $config.mods) {
    $dir = [string]$entry.dir
    if ($Only -and ($Only -notcontains $dir)) { continue }

    $src = Join-Path $root "mods/$dir"
    $manifestPath = Join-Path $src "mod.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw "找不到清单：$manifestPath" }
    $manifest = [IO.File]::ReadAllText($manifestPath, [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    $id = [string]$manifest.id
    $version = [string]$manifest.version
    if ($id -ne $dir) { Write-Warning "目录名($dir) 与 mod.json 的 id($id) 不一致；安装目录按 id 走" }

    Write-Host ""
    Write-Host "=== $id $version ==="

    $pck = Join-Path $out "$id.pck"
    if (Test-Path -LiteralPath $pck) { Remove-Item -LiteralPath $pck -Force }
    & (Join-Path $root "tools/pack.ps1") -Godot $Godot -ModId $id -Source $src -Output $pck

    $stage = Join-Path $out "stage-$id"
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Copy-Item -LiteralPath $manifestPath -Destination $stage
    Copy-Item -LiteralPath $pck -Destination (Join-Path $stage "$id.pck")
    if (Test-Path -LiteralPath (Join-Path $src "icon.png")) {
        Copy-Item -LiteralPath (Join-Path $src "icon.png") -Destination $stage
    }
    foreach ($bundle in $entry.bundle) {
        $from = Join-Path $root ([string]$bundle.from)
        $to = Join-Path $stage ([string]$bundle.to)
        if (-not (Test-Path -LiteralPath $from)) { throw "bundle 源目录不存在：$from" }
        New-Item -ItemType Directory -Path $to -Force | Out-Null
        Copy-Item -Path (Join-Path $from "*") -Destination $to -Recurse -Force
    }

    $zip = Join-Path $out "$id-$version.zip"
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
    Remove-Item -LiteralPath $stage -Recurse -Force
    Remove-Item -LiteralPath $pck -Force

    Write-Host "已生成：$zip"
    $built += $zip
}

if ($built.Count -eq 0) { throw "没有构建任何 mod（检查 -Only 或 build.config.json）" }
Write-Host ""
Write-Host "完成，共 $($built.Count) 个包："
$built | ForEach-Object { Write-Host "  $_" }
