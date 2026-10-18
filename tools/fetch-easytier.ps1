<#
.SYNOPSIS
  取得 EasyTier 官方可执行文件到 vendor/easytier/<平台>/，供打包随 Mod 分发。

.DESCRIPTION
  两种来源：
    1. -FromDir <已解压目录>：直接用本地已有的 easytier-core / easytier-cli（离线可用）。
    2. 默认：按 vendor/easytier/tools.json 里固定的 URL 下载官方发布 zip 并解压，再逐个校验 SHA-256。
  校验不通过会报错退出，绝不放行来源不明的二进制。许可全文与 NOTICE 已随仓跟踪
  （vendor/easytier/notice/），不在这里下载。

.EXAMPLE
  .\tools\fetch-easytier.ps1 -FromDir E:\tools\easytier-windows-x86_64
  .\tools\fetch-easytier.ps1
#>
param(
    [string]$Platform = "windows-x86_64",
    [string]$FromDir = "",
    [string]$OutDir = ""
)
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $root "vendor/easytier/tools.json"
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "找不到 tools.json：$manifestPath" }

$manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
# 注意：不要把 -Platform 参数赋给 $platform，同名变量会被强转成 string。
$spec = $manifest.platforms.$Platform
if ($null -eq $spec) { throw "tools.json 未定义平台：$Platform" }

if ($OutDir -eq "") { $OutDir = Join-Path $root "vendor/easytier/$Platform" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if ($FromDir -ne "") {
    if (-not (Test-Path -LiteralPath $FromDir)) { throw "源目录不存在：$FromDir" }
    Write-Host "从本地目录复制：$FromDir"
    foreach ($name in $spec.files.PSObject.Properties.Name) {
        $src = Join-Path $FromDir $name
        if (-not (Test-Path -LiteralPath $src)) { throw "源目录缺少 $name" }
        Copy-Item -LiteralPath $src -Destination (Join-Path $OutDir $name) -Force
    }
} else {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("easytier-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $zip = Join-Path $tmp $spec.asset
        Write-Host "下载 $($spec.url)"
        Invoke-WebRequest -Uri $spec.url -OutFile $zip -TimeoutSec 600
        Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
        foreach ($name in $spec.files.PSObject.Properties.Name) {
            $found = Get-ChildItem -LiteralPath $tmp -Recurse -File -Filter $name | Select-Object -First 1
            if ($null -eq $found) { throw "发布包内未找到 $name" }
            Copy-Item -LiteralPath $found.FullName -Destination (Join-Path $OutDir $name) -Force
        }
    } finally {
        $resolved = [IO.Path]::GetFullPath($tmp)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($resolved) -like "easytier-*") {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}

$bad = 0
foreach ($entry in $spec.files.PSObject.Properties) {
    $path = Join-Path $OutDir $entry.Name
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $ok = ($actual -eq $entry.Value)
    Write-Host ("{0,-20} {1} {2}" -f $entry.Name, $(if ($ok) { "OK  " } else { "BAD " }), $actual)
    if (-not $ok) { $bad++ }
}
if ($bad -gt 0) { throw "SHA-256 校验失败（$bad 个文件）：请确认版本是否为 $($manifest.easytier_version)" }

$notice = Join-Path $root "vendor/easytier/notice"
foreach ($f in @("EASYTIER_NOTICE.md", "LICENSE.easytier")) {
    if (-not (Test-Path -LiteralPath (Join-Path $notice $f))) { throw "缺少许可文件：vendor/easytier/notice/$f" }
}
Write-Host "完成：$OutDir（$($manifest.easytier_version)，许可文件见 vendor/easytier/notice/）"
