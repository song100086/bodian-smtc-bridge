# 波点音乐 SMTC 桥接 / Bodian SMTC Bridge

给 **波点音乐** 桌面客户端补上 Windows **SMTC**（System Media Transport Controls，系统媒体传输控件）媒体会话。

补上之后，**任何读取 SMTC 的软件**都能识别波点正在播放什么：

- Windows 自带的**媒体控件**（按音量键弹出的那张卡片）
- **Lyricify Fusion**（滚动歌词 / 桌面 / 任务栏歌词）
- 其它任务栏歌词工具、SMTC 类小工具
- 键盘上的媒体键（▶⏸ / ⏭ / ⏮）
- Discord Rich Presence 之类的 SMTC 桥接

> 本项目与任何具体客户端无关。**Lyricify Fusion 只是我们验证过的消费者之一**。

## 为什么需要它

波点音乐桌面客户端（Flutter + `media_kit`/libmpv）**从不发布 SMTC 媒体会话**：
音量键弹出的媒体控件里看不到它，任何歌词软件也识别不到它（通常表现为「无可用播放源」）。

SMTC 是 Windows 上媒体信息的**标准通道**，于是本桥接在一个独立进程里**发布一个真实可用的
SMTC 会话**，把波点正在播放的内容喂给它：

| 数据 | 来源 |
|---|---|
| 曲目（歌名 / 歌手 / 专辑 / 时长） | 波点自己的数据库 `%LOCALAPPDATA%\cn.wenyu.bodian\bodian_pc\database\songDB.db` 的 `hist_song` 表 |
| 播放进度 / 暂停状态 | 读取 `bodian_pc.exe` 进程内存中 mpv 的 `time-pos` |
| 专辑封面 | 数据库中的封面地址（`.webp` → `.jpg`） |
| 传输控制（上一首 / 下一首 / 播放暂停） | `MediaPlayer` + 静音播放列表 + `CommandManager`，再把按钮转发为媒体键交给波点 |

## 提供的 SMTC 能力

- ✅ 媒体会话本身（让系统与各客户端"看见"波点）
- ✅ 曲目元数据：歌名 / 歌手 / 专辑
- ✅ 播放状态：播放 / 暂停
- ✅ 时间轴：精确进度（含暂停、拖动）
- ✅ 专辑封面缩略图
- ✅ 传输控制：⏮ 上一首 / ⏭ 下一首 / ▶⏸ 播放暂停
- ✅ 媒体卡片 / 客户端中显示为 **波点音乐**（设置 AppUserModelID + 注册开始菜单快捷方式），而不是 powershell.exe 或「未知应用」
- ❌ 跳转进度（seek）：见「已知限制」

## 安装

**依赖**：Windows 10/11、**Windows PowerShell 5.1**（系统自带）、[Node.js](https://nodejs.org/)
（仅用于下载专辑封面；没有 Node 时其余功能照常，只是没有封面）

1. 把本目录所有文件放到同一目录，推荐 `%LOCALAPPDATA%\BodianSmtcBridge\`
2. 双击 **`bodian-smtc-bridge.vbs`** 启动（**无窗口**、后台常驻）
3. 打开你的 SMTC 客户端（例如 Lyricify Fusion），即可看到波点当前播放的曲目
4. 开机自启：把 `bodian-smtc-bridge.vbs` 的**快捷方式**放进启动文件夹
   （`Win+R` → 输入 `shell:startup` 回车）

## 文件

| 文件 | 说明 |
|---|---|
| `bodian-smtc-bridge.ps1` | 桥接主脚本（PowerShell 5.1 / STA） |
| `bodian-smtc-bridge.vbs` | 无窗口启动器（推荐用它启动） |
| `bodian-smtc-bridge.cmd` | 备用启动器（会闪一下控制台） |
| `cover_dl.js` | 封面下载器（Node） |
| `verify_session.ps1` | 诊断工具：查看当前系统的 SMTC 播放源 |
| `DIAGNOSIS.md` | 完整技术诊断与实现记录（原理、API 细节、踩坑、可行性论证） |

## 已知限制

- **媒体卡片的应用名**依赖首次启动时在开始菜单创建的 `波点音乐.lnk`（其 `AppUserModelID` 属性与桥接的 AUMID 一致，shell 靠它解析显示名）。删除该快捷方式后，媒体卡片会退回「未知应用」

- **跳转进度（seek）不可用**：客户端的跳转请求通过 `PlaybackPositionChangeRequested`
  事件下发，而 PowerShell 无法订阅 WinRT 事件（这是「下一首」能实现而「seek」不能的根本原因）；
  并且媒体键没有「定位」功能，执行端还需向波点进程注入 mpv 命令。详见 `DIAGNOSIS.md`
- **波点客户端升级后**，若歌词/进度不再跟随，多半是内存偏移变了
  （`media_kit_native_event_loop.dll + 0xA1D8`、`MPContext + 0x328`），需要重新定位
- **系统 TLS 损坏时**（例如 `curl` 报 `SEC_E_NO_CREDENTIALS`），SMTC 自己下载不了封面，
  本脚本改用 Node 下载；正常系统两者皆可
- 脚本按默认安装路径 `C:\Program Files (x86)\bodian` 定位 `sqlite3.dll`，
  波点装在别处时需要修改
- 仅在特定波点版本上验证过，欢迎反馈

## 免责声明

非官方工具，仅供学习与个人使用。所有数据均取自本机波点客户端，
不破解、不绕过任何会员或版权限制。

## 许可

MIT


