# EasyTier 第三方组件声明 / Third-party notice

本目录（`tools/`）随 ETN Coop EasyTier 拓展 Mod 一起分发 EasyTier 的官方可执行文件：

| 项目 | 值 |
|---|---|
| 组件 | EasyTier（`easytier-core`、`easytier-cli`） |
| 版本 | 2.6.4（官方发布 tag `v2.6.4`） |
| 来源 | <https://github.com/EasyTier/EasyTier/releases/tag/v2.6.4> |
| 许可证 | **GNU Lesser General Public License v3.0（LGPL-3.0）**，全文见同目录 `LICENSE.easytier` |
| 是否修改 | **未修改**，直接使用官方发布的可执行文件（SHA-256 见 `mod_sdk/coop_easytier_mod/tools.json`） |

## 对应源码（LGPL-3.0 §4）

未被修改的对应源码可从上游获取，无需另行索取：

- 仓库：<https://github.com/EasyTier/EasyTier>
- 本包所用版本：<https://github.com/EasyTier/EasyTier/tree/v2.6.4>
- 发布包：<https://github.com/EasyTier/EasyTier/releases/tag/v2.6.4>

如需要，我们也可提供该版本源码的副本：请在 Mod 发布页留言索取（书面承诺，有效期三年）。

## 与本体/Mod 的关系

- EasyTier 作为**独立程序**由 Mod 以子进程方式启动（`OS.execute_with_pipe`），并通过其自带的命令行与本地 RPC 通信。
- Mod 与游戏本体**不链接、不包含** EasyTier 的代码，因此不属于 LGPL-3.0 意义上的组合作品（combined work）；本声明只覆盖 `tools/` 目录下的第三方二进制。
- 替换/删除 `tools/` 目录不影响 Mod 其它部分；玩家也可以自行提供同版本或兼容版本的 `easytier-core` 与 `easytier-cli`。

## 兼容性提示

游戏内 EasyTier 后端按官方 v2.6.4 的行为实现（`--no-tun`、`--dhcp`、`--port-forward`、`--hostname`、`connector list` / `peer` 的 JSON 输出）。使用其它版本时，就绪检测所需的 CLI 字段可能不同。
