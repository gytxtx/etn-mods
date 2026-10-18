# etn_trainer / 修改器 mod

游戏内作弊面板。按 **F1** 开关；局内打开会自动暂停，主菜单/商店打开不暂停。

## 页面

| 页 | 内容 |
|---|---|
| 数值 | 移速 / 射速 / 伤害 / 拾取范围 倍率滑条（0.1x–10x）、无敌、秒杀、三档预设 |
| 资源 | 金币加减（局内，不写存档）、青辉石（元货币，写存档，二次确认） |
| 解锁 | 角色 / 服装 / 支援 一键解锁（写存档，二次确认）；游戏模式不在范围内 |
| 辅助 | 额外减伤上限、护甲值加算、回满血 |
| 调试 | 清屏、刷指定敌人、结束本回合、在场敌人/回合/倒计时 |
| 关于 | 版本、开发者模式开关（只改内存，不写 config.ini）、HUD 开关、全部重置 |

## 行为约定

- **倍率每局归零**，不写存档；面板位置与 HUD 开关记在 `user://etn_trainer.cfg`。
- 倍率注入挂在 `PlayerData.player_ability_changed_end`：每次属性重算后重新乘一次，
  因此关开关即还原，且不会吞掉本局的自然成长（`reset_date()` 后也会自动重新生效）。
- 无敌走 `health_component.is_invincible`（会挡治疗，回血按钮内部临时关掉再治）。
- **联机会话（`ExtensionHooks.is_lan_session`）下整体只读禁用**，防止污染他人房间。
- 面板挂在 `get_tree().root` 下，打开时会把自己移到 root 末尾——本体 GUI 命中测试按
  场景树逆序走，不这么做会被新场景的背景 Control 抢走鼠标事件。

## 依赖

- 本体 **v0.5.1.4 及以上**（`Game.version_number`），`ModAPI.VERSION = 2`。

## 已知限制

- `tools/pack_mod.gd` 原样打包，**打不进 PNG 贴图**：`icon.png` 靠 zip 内的独立文件
  被安装器解到 `user://mods/etn_trainer/icon.png`，不在 pck 里。若将来需要贴图/翻译资源，
  改用本体工程副本 + `ModPack` 导出预设的构建路径。
- 面板字号/尺寸按本体基准分辨率 **640×360** 设计，改动前先确认 `project.godot` 的 stretch 设置。
- 无头自检：`--headless --path <本体工程> --quit-after 400 -- --trainer-selftest [--trainer-scene=res://scenes/main/test_room.tscn]`。
