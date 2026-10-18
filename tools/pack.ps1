<#
.SYNOPSIS
  把单个 mod 源目录打成 <ModId>.pck（不依赖本体工程，也不安装到 user://mods）。

.DESCRIPTION
  移植自 Enter-The-Nyangeon 的 mod_sdk/pack_mod_source.ps1：
    1. 在系统临时目录建一个最小工程（只需 config_version=5），拷入 tools/pack_mod.gd；
    2. 把源目录快照到临时目录（排除 *.pck 与 *.md，README 不进包）；
    3. 注入 mod_build.json（build_id / git sha）便于追溯；
    4. 隔离 APPDATA/LOCALAPPDATA/XDG_DATA_HOME 后 headless 打包，不碰已安装的 MOD。

.EXAMPLE
  .\tools\pack.ps1 -Godot C:\godot\Godot_v4.7-stable_win64_console.exe -ModId etn_trainer -Source mods/etn_trainer -Output dist/etn_trainer.pck
#>
param(
    [string]$Godot = $env:GODOT_BIN,
    [Parameter(Mandatory = $true)][string]$ModId,
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Output,
    [string]$BuildId = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

if ([string]::IsNullOrWhiteSpace($Godot)) {
    throw "未指定 Godot：用 -Godot <路径>，或设置环境变量 GODOT_BIN"
}
if (-not (Test-Path -LiteralPath $Godot)) { throw "找不到 Godot 可执行文件：$Godot" }
$src = (Resolve-Path -LiteralPath $Source).Path
if (-not (Test-Path -LiteralPath (Join-Path $src "mod.json"))) { throw "找不到 mod.json：$src\mod.json" }

if ($BuildId -eq "") {
    $sha = (git -C (Split-Path -Parent $PSScriptRoot) rev-parse --short HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $sha) {
        $dirty = (git -C (Split-Path -Parent $PSScriptRoot) status --porcelain 2>$null)
        $BuildId = $sha.Trim() + $(if ($dirty) { "-dirty" } else { "" })
    } else {
        $BuildId = "local-" + (Get-Date -Format "yyyyMMddHHmmss")
    }
}

$outPck = [IO.Path]::GetFullPath($Output)
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$taskRoot = Join-Path $tempRoot ("etn-mod-pack-" + [Guid]::NewGuid().ToString("N"))
$stage = Join-Path $taskRoot "source"
$tmpPck = Join-Path $taskRoot "$ModId.pck"
$envBackup = @{}
try {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Get-ChildItem -LiteralPath $src -Recurse -File -Force | Where-Object {
        $_.Extension -ne ".pck" -and $_.Extension -ne ".md"
    } | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($src), $_.FullName)
        $target = Join-Path $stage $relative
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $target
    }
    $stamp = @{ build_id = $BuildId; mod_id = $ModId } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $stage "mod_build.json"), $stamp, [Text.UTF8Encoding]::new($false))

    # 最小工程：不需要本体工程，也不需要导入缓存。
    [IO.File]::WriteAllText((Join-Path $taskRoot "project.godot"), "config_version=5" + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "pack_mod.gd") -Destination (Join-Path $taskRoot "pack_mod.gd")

    foreach ($key in @("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME")) {
        $envBackup[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
        $isolated = Join-Path $taskRoot $key
        New-Item -ItemType Directory -Path $isolated -Force | Out-Null
        [Environment]::SetEnvironmentVariable($key, $isolated, "Process")
    }

    $packOutput = & $Godot --headless --path $taskRoot --script res://pack_mod.gd -- `
        "--mod-source=$stage" "--out=$tmpPck" "--mod-id=$ModId" 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -or -not (Test-Path -LiteralPath $tmpPck) -or ($packOutput -match "SCRIPT ERROR|ERROR:|add_file failed")) {
        throw "打包失败（exit=$exit）：$($packOutput -join [Environment]::NewLine)"
    }
    $packOutput | Select-String "PACK_MOD" | ForEach-Object { $_.Line }

    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($outPck)) -Force | Out-Null
    Move-Item -LiteralPath $tmpPck -Destination $outPck -Force
    $size = (Get-Item -LiteralPath $outPck).Length
    Write-Host "已生成：$outPck（$size 字节，build=$BuildId）"
} finally {
    foreach ($key in $envBackup.Keys) {
        [Environment]::SetEnvironmentVariable($key, $envBackup[$key], "Process")
    }
    $resolved = [IO.Path]::GetFullPath($taskRoot)
    if ($resolved.StartsWith($tempRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolved) -like "etn-mod-pack-*") {
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
