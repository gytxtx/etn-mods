# Changelog

## etn_coop_easytier 0.1.1

- 适配官方联机菜单 2026-10-18 的卡片化 UI：页面不再自带 `ScrollContainer`，改为内容高度的卡片容器，随官方 `PageScroll` 滚动
- 房间码 / 高级选项 / 连接改为卡片布局，沿用官方字体与控件主题；复制与校验提示显示在对应卡片内
- Android 外置页同步卡片化，改用官方滚动区处理触屏拖动

## etn_coop_easytier 0.1.0

从《Enter The Nyangeon》主仓分支 `feat/coop-easytier-extension` 迁入（源码、构建脚本与许可声明）。

- 桌面：管理 EasyTier 组网（房间码、加入/离开、节点状态）
- Android：提供外置客户端配置与 LAN 加入引导
- 随包分发 EasyTier 2.6.4 官方二进制（LGPL-3.0，未修改，子进程调用）
- 依赖官方联机 Mod `etn_coop`（扩展接口 v1）

## etn_trainer 0.1.0

首个独立发布版，从《Enter The Nyangeon》主仓的 `mods/etn_trainer` 迁出。

- 数值：移速 / 射速 / 伤害 / 拾取范围 倍率、无敌、秒杀、三档预设
- 资源：金币（局内）、青辉石（写存档，二次确认）
- 解锁：角色 / 服装 / 支援
- 辅助：减伤上限、护甲加算、回满血
- 调试：清屏、刷敌人、结束回合、状态查看
- 联机会话下整体只读禁用
