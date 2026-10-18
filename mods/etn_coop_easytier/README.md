# EasyTier Extension / 官方联机 Mod 的 EasyTier 拓展

`etn_coop_easytier` 是依赖 `etn_coop` 的独立 Mod。官方联机 Mod 管理握手、玩家与实体同步、准备房、回合和重连；本拓展仅管理 EasyTier 组网、房间码、设置页与自有后台进程。

拓展包只包含 `res://mods/etn_coop_easytier/`，manifest 声明 `dependencies: ["etn_coop"]`，不设置 `replace_files` 或 `replace_paths`。后续 EasyTier 修改集中在本目录，不需要继续修改官方 `CoopNet` 或本体 `ExtensionHooks`。

## Compatibility / 兼容性

- 需要带 **官方联机拓展接口 v1 及 `get_menu_pages()` 页签能力** 的 `etn_coop`。旧官方包没有能力时，会显示明确更新告警，不执行拓展连接逻辑。
- 依赖加载由本体 `ModManager` 拓扑排序处理，缺少/禁用官方 Mod 时拓展也会停用。
- 当前官方协议为 v4、Mod 版本为 `0.1.11`；页签改动没有修改 RPC 方法或握手载荷。拓展自身版本独立为 `0.1.0`。
- 当前工具清单固定为官方 EasyTier `2.6.4` Windows x86_64；后端也允许显式指定其它桌面平台的 core/cli，但本轮仅验证 Windows，不承诺其它版本 CLI 兼容。
- Android 自动显示外置客户端引导，不创建桌面进程后端；需要玩家另装 EasyTier Android 客户端。此模式无需重打游戏 APK，不包含手机内置组网或客户端连接状态检测。

## Use / 使用

1. 更新官方 `etn_coop` 至包含拓展接口 v1 的构建，再导入 `build/etn_coop_easytier_0.1.0.zip`，启用两个 Mod 并重启游戏。
2. 在官方 COOP 菜单左侧选择 **EasyTier** 页签。整个页面支持滚动，房间码、高级参数和连接按钮随页面一起移动；高级入口在提示行右侧，高级选项内部不再单独滚动。端口/虚拟 IP 在宽布局中并排，窄于 400 设计像素时自动单列，支持触屏、键盘及手柄导航。
3. 房主生成/复制房间码并开房，伙伴粘贴同一码加入。跨网联机前需在高级选项里确定入口节点（点「使用公益节点」或填自建地址）；端口、虚拟地址和 core 路径也在那里覆盖，客机默认 DHCP，并自动发现房主端口。
4. 「取消 / 断开」关闭本拓展连接和进程；F12、普通离场和退出游戏也会清理。切换页签或关闭联机菜单保留表单和后台连接。

准备、连接、失败与离线状态统一显示在联机菜单底部；切换页签不会丢失失败原因。高级参数在连接期间仍可展开查看，输入和开房/加入操作锁定。请同时更新官方联机包与拓展包，以使用统一状态栏。

入口节点**默认留空**：留空＝不使用入口节点（仅局域网或可直连时可用）。跨网联机请在高级选项里点入口输入框右侧的「使用公益节点」，填入 ETN 自建中继的域名 `udp://et.saibamidori.com:11010`（A 记录指向 `154.9.252.96`，2026-10-14 经域名实测可正常组网），也可以直接填自建节点地址。域名只是别名：节点仍监听 `11010` UDP+TCP，直接写 IP 同样可达；换机器时只需改 DNS，不必再发版。

房间码会派生组网密码，只在内存和系统剪贴板中使用，不写入设置或日志。`user://etn_coop_easytier.cfg` 继续只保存非凭据字段；后台凭据写入 `user://etn_easytier/<随机名>.toml`，在准备完成、取消或失败后删除。强制杀死整个游戏进程来不及执行退出清理，这类残留文件会在下次启动时连同旧版系统缓存目录里的同类文件一并清除。

## Android External Client / Android 外置客户端

1. 手机安装本拓展和兼容的官方联机 Mod，另从 [EasyTier 官方下载页](https://www.easytier.cn/guide/download.html)安装 Android 客户端。
2. 电脑房主照常在游戏 EasyTier 页签组网开房，并分享房间码及实际入口节点。
3. 手机在游戏 EasyTier 页签粘贴同一码，分别复制网络名称、密码和入口节点，填写到外置客户端。支持粘贴「房间码@入口」，也可手动改入口；公益节点仍需显式点击，不自动填写。
   - Astral 2.9.60：添加房间时关闭「是否保护」，将组网名称填入「房间号」、组网密码填入「房间密码」；默认的保护房间会自动生成其它凭据，不能只把房间显示名改成 Mod 的组网名称。
4. 在外置客户端启用 VPN/TUN 和自动分配虚拟 IP（DHCP），允许游戏使用该 VPN，完成连接后返回游戏。若客户端没有可用的系统 VPN 接入，单纯使用 no-TUN 模式不能按此流程直接访问房主虚拟 IP。
5. 核对房主虚拟 IP 与游戏端口，点「复制 LAN 加入地址」，切换游戏 LAN 页签，把 `IP:端口` 粘贴到房主 IP 输入框后加入。默认 `10.144.144.1:24591` 仅是初始参考值，不能替代房主实际配置。

Android 页面不提供桌面 core 路径、组网监听端口、组网开房/加入或取消按钮；复制操作不调用官方 `start_backend`，不会先关闭已有游戏会话。页面不声明组网成功，外置 VPN 状态以客户端显示为准。离房、退出游戏或卸载本拓展均不负责停止外置客户端，请玩家自行断开。密码以掩码显示，可显式复制；房间码及派生凭据不写入设置。当前不导出客户端专用配置文件，也不自动启动/控制外置 App。

## Build / 构建

1) 取二进制（不入库，`vendor/easytier/windows-x86_64/`）：

```powershell
.\tools\fetch-easytier.ps1 -FromDir <官方工具目录>
```

也可不指定 `-FromDir`，按 `vendor/easytier/tools.json` 的固定 URL 下载。所有二进制逐文件校验 SHA-256。

2) 打包：

```powershell
.\build.ps1 -Godot <godot.exe> -Only etn_coop_easytier
```

产出 `dist/etn_coop_easytier-0.1.0.zip`：本拓展 PCK、manifest，以及 `tools/easytier-windows-x86_64/` 松散工具（含 LGPL 许可与 NOTICE）。构建不会安装 Mod，也不修改官方 Mod 源码或玩家目录。

Android 用瘦包即可（不需要 core/cli）：把 `build.config.json` 里本 mod 的 `bundle` 两条暂时删掉再打包，得到的 zip 依赖和 Mod ID 与通用包一致，两者任选其一安装。桌面瘦包仍需玩家自行提供 core/cli。

第三方组件说明见 [EASYTIER_NOTICE.md](../../vendor/easytier/notice/EASYTIER_NOTICE.md)，版本与哈希见 [tools.json](../../vendor/easytier/tools.json)，许可全文见 [LICENSE.easytier](../../vendor/easytier/notice/LICENSE.easytier)。

## Verification / 验证

在《Enter The Nyangeon》主仓运行（回归脚本与官方 Mod 都在那边）：

```powershell
python tests/run_coop_extension_checks.py --core <本仓>/vendor/easytier/windows-x86_64/easytier-core.exe
```

检查通用接口契约、真实 core 生命周期与 UDP、缺依赖停用、仅官方 Mod 的 LAN 双端准备房、两个 PCK 配合组网/握手/镜像、重连复用后台进程、准备取消和 core 故障回菜单。EasyTier 专用 UI 断言及对应回归入口已按用户要求删除。所有运行使用隔离 user://，不接触玩家存档或已安装包。

图形退出时的两条纹理告警必须与同次仅官方 Mod 的基线对比；无窗口网络回归仍不接受此类错误。此验证不替代公网 NAT、弱网、Android 或全部角色技能回归。

2026-10-17 验证：隔离 Godot 4.7 工程模拟 Android 平台路由，确认不创建桌面后端、不调用会话启动接口，桌面仍委托官方接口；Android 精简 ZIP 和通用 ZIP 均从实际 PCK 挂载后通过同样检查。已人工检查中文 440 与英文 336 设计像素宽页面、配置复制与 LAN 地址复制，未新增 EasyTier UI 自动断言。底层真实 core/UDP 回归通过；整套桌面集成回归中双端握手与重连复用进程完成，但当前官方接口未消费 `share_label_key`，旧房间标签断言失败，另有本地 `godot_ai` autoload 缺失日志，故不能宣称整套通过。Android 真机、外置客户端 VPN 路由及公网互联仍待验证。

同日真机补充：Pixel 5 / Android 14 / Astral 2.9.60（内核 2.6.4）已完成相同派生参数的外置组网，`tun0` 实际取得 `10.144.144.2/24`，手机到房主 `10.144.144.1` 的 4 次 ping 全部成功，平均约 10.3 ms。数据走同一物理 LAN 内的 P2P；未验证跨网或强制服务器转发。手机已安装本体缺少 `ModAPI.create_option_tab()`，当前官方联机 Mod 因此解析失败，游戏握手与手机引导页尚未通过；需先更新到具备对应接口的本体。完整记录：`.godot/android_easytier_device_20261017/RESULT.md`。测试结束已断开连接、清理临时配置，并撤回本次安装的不兼容 Mod 文件。

本体更新后复测（同日）：当前源码 Android 本体已安装，官方 Mod 和 Android 引导均能加载；手机实际从外置 VPN 下的 LAN 入口加入电脑，双方握手、准备房和玩家镜像生成通过。触摸输入已补显式聚焦/软键盘，Android 滚动包装页复用本体 `ScrollBox.gd`，解决 `emulate_mouse_from_touch=false` 下输入和拖动无响应。当前交付包已包含这两项修复，桌面模式不变；平台回归仍通过。最终启动日志无脚本错误；切换 App 时曾出现一次 Vulkan surface 丢失告警，完整关卡和跨网中继仍待测。记录：`.godot/android_base_update_20261017/RESULT.md`。

拓展作者接口与生命周期约定见 [docs/COOP_EXTENSIONS.md](../../docs/COOP_EXTENSIONS.md)。
