# ETN Mods

《Enter The Nyangeon》的 Mod 集合仓。每个 mod 独立版本、独立发布包，共用一条打包流水线。

| Mod | 目录 | 说明 |
|---|---|---|
| `etn_trainer` | [`mods/etn_trainer/`](mods/etn_trainer/) | 内置修改器，F1 开关 |
| `etn_coop_easytier` | [`mods/etn_coop_easytier/`](mods/etn_coop_easytier/) | 官方联机 Mod 的可选组网拓展（依赖 `etn_coop`），随包分发 EasyTier 官方二进制 |

## 目录结构

```
mods/<id>/          每个 mod 的源根；目录内容按 res://mods/<id>/ 打进 pck
tools/pack_mod.gd   打包器（PCKPacker，原样打包，不做资源导入）
tools/pack.ps1      单个 mod 的 pck 构建（临时最小工程 + 隔离 APPDATA）
build.ps1           按 build.config.json 遍历构建，产出 dist/<id>-<version>.zip
build.config.json   参与构建的 mod 列表与额外产物（如 etn_coop_easytier 的 tools/）
```

`mods/<id>/` 里的 `*.md` 与 `*.pck` **不会**打进 pck；`.gd.uid` 会保留，用于稳定脚本 UID。

## 依赖

- **本体**：`v0.5.1.4` 及以上（`Game.version_number`），`ModAPI.VERSION = 2`。
- **官方联机 Mod**：`etn_coop`（仅 `etn_coop_easytier` 需要，扩展接口 v1）。
- **Godot**：`4.7-stable`（pck 版本必须与本体一致）。
- 构建**不需要**本体工程，也不需要导出模板。

## 第三方二进制（仅 etn_coop_easytier）

`etn_coop_easytier` 随包分发 EasyTier 官方可执行文件，构建前先取二进制：

```powershell
.\tools\fetch-easytier.ps1                                            # 联网下载 v2.6.4 并校验 SHA-256
.\tools\fetch-easytier.ps1 -FromDir E:\tools\easytier-windows-x86_64  # 用本地已解压目录
```

- 二进制落在 `vendor/easytier/windows-x86_64/`（**不入库**，`.gitignore` 已排除）。
- 版本、URL、SHA-256 固定在 `vendor/easytier/tools.json`；许可全文与 NOTICE 入库在 `vendor/easytier/notice/`。
- 打包时由 `build.config.json` 的 `bundle` 拷进 zip 的 `tools/easytier-windows-x86_64/`：安装器把整个 zip 解到 `user://mods/<id>/`，后端在该目录查找二进制。

## 构建

```powershell
.uild.ps1 -Godot "D:\Godot Engine\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe"
```

- 只构建其中一个：`-Only etn_trainer`
- 也可以用环境变量：`$env:GODOT_BIN = "...console.exe"; .\build.ps1`
- 产物在 `dist/`：`<id>-<version>.zip`，zip 根目录是 `mod.json` + `<id>.pck` + `icon.png`。

## 安装

游戏内：主菜单左下角 **MOD** → **导入 zip** → 选 `dist/*.zip` → **重启游戏**（pck 只在新进程挂载，无热重载）。

手动：把 zip 内容解到 `%APPDATA%\Godot\app_userdata\Enter The Nyangeon\mods\<id>\`。

## 发布

- 版本号写在各自 `mods/<id>/mod.json` 的 `version`。
- tag 与 mod 对应：`etn_trainer-v0.1.0`、`etn_coop_easytier-v0.1.0`。
- CI（`.github/workflows/build.yml`）在打 tag 时构建全部 mod 并附到 Release。

## 已知限制

`tools/pack_mod.gd` 是**原样打包**：没有资源导入，所以 pck 里不能有需要导入的贴图/字体/`.translation`。
`icon.png` 因此作为 zip 里的独立文件被安装器解到安装目录，不放进 pck。
将来若某个 mod 需要贴图或 CSV 翻译，构建必须改为「本体工程副本 + `ModPack` 导出预设」（参考本体仓 `mod_sdk/README.md` §6–§7）。

## 许可

本仓代码以 [MIT](LICENSE) 发布（Copyright © 2026 KFACBT）。
随包分发的第三方组件按其自身许可分发：EasyTier 为 LGPL-3.0，声明与全文见 [`vendor/easytier/notice/`](vendor/easytier/notice/)。
