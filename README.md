# Elsewhere

一个 macOS 菜单栏小工具：一键把 iPhone 的定位改到代理出口所在的城市，或者任意你想去的地方。

> Elsewhere is a tiny macOS menu-bar app that changes a connected iPhone's or iPad's location — to your proxy's exit IP, a favorite city, or any spot on the map. It talks to the device itself through a built-in helper (based on [idevice](https://github.com/jkcoxson/idevice)), so Xcode is not required. No jailbreak, no profiles, nothing installed on the phone.

- **跟随代理出口**：查当前出口 IP 的位置，一键把定位改过去。出口可以按这台 Mac 查（走系统代理，和 Surge 等工具一致），也可以按手机查（经手机代理 App 的「代理共享」）
- **出口变化提醒 / 自动跟随**：在 Surge 里换了节点，自动发现并提醒，或者直接跟着改
- **常用城市**：内置 11 个城市，可以增删、拖动排序
- **主窗口**：侧边栏分「定位、地图、常用城市、设备、设置」，背景是会动的字符场；菜单栏面板只放常用操作，点「打开 Elsewhere」进入主窗口
- **地图**：大地图上点一下就能选点，也可以搜地名或输入坐标；地图上同时标出 iPhone 当前位置和代理出口，选好后一键「应用到 iPhone」（⌘↩），也能直接恢复真实定位
- **海外地名也搜得到**：国区 Mac 的 Apple 地图用的是高德数据，海外地名基本搜不出来。Elsewhere 同时用 OpenStreetMap 搜索：边输入边联想，回车精确搜索，「东京塔」「埃菲尔铁塔」这样的中文名也能找到
- **恢复真实定位**：一个按钮
- **重启后自动改回**：设备重启会让模拟定位失效；重新连接时，Elsewhere 自动改回上次的位置（可在设置里关闭）
- **时区检查**：设备时区和定位对不上时提醒你，并按设备给出改法
- **快捷指令**：「跟随代理出口」「改到常用城市」「改到坐标」「恢复真实定位」可以在快捷指令里使用和组合
- **多台设备**：可以一次修改所有连着的 iPhone 和 iPad
- **不需要 Xcode**：内置连接组件，下载就能用；插线或无线都可以
- **自动识别 iPhone 和 iPad**：插线自动识别，连不上时告诉你原因（没插线、没信任、没开开发者模式）
- **全局快捷键** `⌃⌥⌘L`：随时跟随出口，结果用系统通知告诉你
- **只改定位也行**：「设置 › 代理出口功能」关掉后，不再查询出口 IP，跟随出口、出口提醒和快捷键都会隐藏
- 开机自启、深浅色模式、中文界面

## 原理

用的是 Xcode 调试时那个「模拟定位」：iOS 开发者服务里的位置模拟，和 `xcrun devicectl device simulate location` 是同一个接口。

- 不越狱、不装描述文件或根证书，手机上不装任何 App
- 对所有 App 和系统服务生效
- 拔线后定位仍然保持；**设备重启后会恢复真实定位**，需要重新连线再改一次

Elsewhere 有两种方式，在「设置 › 定位方式」里选，默认「自动」：

| 方式 | 怎么连 | 需要 |
| --- | --- | --- |
| **内置** | App 自带的 `elsewhere-helper`（基于开源的 [idevice](https://github.com/jkcoxson/idevice)），通过 macOS 自带的 usbmuxd 连接 | 数据线，或开启无线连接 |
| **Xcode** | Xcode 的 `devicectl` | 安装 Xcode |

「自动」会优先用内置方式；只有 Xcode 能连上的设备交给 Xcode（比如只和 Xcode 做过无线配对的设备），内置方式失败时也会自动换 Xcode 再试。

**无线连接**：设备插线时，点面板里的「允许无线连接」（等同于访达里的「连接 Wi-Fi 时显示此 iPhone」）。之后只要设备和 Mac 在同一个 Wi-Fi 上，拔线也能改定位。

还需要在设备的「设置 › 无线局域网」里，点当前网络旁的 ⓘ，把「私有无线局域网地址」设为「关闭」。macOS 靠设备的 Wi-Fi 地址认出它，私有地址和配对时记下的地址不同，Mac 会认不出这台设备。

**开发者组件**：iOS 17 起，改定位前设备上要挂载 Apple 的开发者磁盘映像。装了 Xcode 的话它通常会自动挂好；没挂的话，Elsewhere 第一次用到时会准备一份：Mac 上有 Xcode 或系统自带的 iOS 开发者组件（`/Library/Developer/DeveloperDiskImages`）就直接用本机的，否则下载（约 17 MB，来自 [Apple 官方映像的镜像](https://github.com/doronz88/DeveloperDiskImage)，pymobiledevice3 用的也是它），校验和清单配套后缓存在 `~/Library/Application Support/Elsewhere`。挂载时向 Apple 在线申请这台设备专属的签名，设备只接受 Apple 签过名的映像。

## 系统要求

- macOS 14 或更新版本
- iPhone 或 iPad，iOS 17 或更新版本，打开开发者模式
- Xcode 不是必需的

## 编译和安装

**用 Xcode：** 打开 `Elsewhere.xcodeproj`，按 ⌘R 运行。

**用命令行：**

```bash
scripts/build.sh --install
```

编译 Release 版，复制到 `/Applications/Elsewhere.app` 并打开。App 没有沙盒（要调用内置组件和 `xcrun`），用的是本机 ad-hoc 签名，不需要开发者账号。

编译内置组件需要 Rust：`brew install rust`（或用 [rustup](https://rustup.rs)）。Xcode 构建时会自动用 cargo 编译 `helper/`，放进 `Elsewhere.app/Contents/Helpers`。

发布版用 `TEAM_ID=你的团队ID scripts/release.sh`：Developer ID 签名、提交公证，生成可以直接分发的 zip。

如果用的是别人编译好的 `Elsewhere.app`，第一次打开可能被 Gatekeeper 拦住。在 Finder 里右键点「打开」，或者执行：

```bash
xattr -dr com.apple.quarantine /Applications/Elsewhere.app
```

## 首次使用

1. **连接并信任**：用数据线把 iPhone 连到 Mac，解锁手机，在弹窗里点「信任」并输入锁屏密码。
2. **打开开发者模式**：iPhone 上进入「设置 › 隐私与安全性 › 开发者模式」，打开后按提示重启手机。如果找不到这个选项，先用 Elsewhere 连接一次，或者打开一次 Xcode 并连上手机，选项就会出现。
3. **允许通知**（可选）：第一次启动时允许通知。快捷键和自动跟随的结果，以及「出口变了」的提醒，都靠系统通知发出。
4. 点菜单栏的定位图标，看到「已连接」就可以用了。

第一次改定位时可能要准备开发者组件（下载并挂载），会多花一些时间。

## 常见问题

**恢复真实定位后，iPad 还停在模拟的位置？**
Wi-Fi 版 iPad 没有 GPS，模拟结束后要靠周围的 Wi-Fi 重新算出位置，在这之前会一直显示最后一次的位置。等一会儿，或者到「设置 › 隐私与安全性 › 定位服务」关掉再打开。带 GPS 的 iPhone 一般几秒就回来了。

**手机重启后定位变回来了？**
模拟定位只在本次开机内有效。Elsewhere 开着时，设备重新连接后会自动改回上次的位置（「设置 › 重新连接后恢复定位」）；刚开机还锁着屏的话，解锁后就会改回。想回到真实定位，点「恢复真实定位」即可。

**时区为什么和定位对不上？**
iOS 的「自动设定时区」：没有蜂窝网络的设备（比如 Wi-Fi 版 iPad）会跟着定位走，所以打开它就行；有 SIM 卡的 iPhone 以运营商网络为准，不跟模拟定位，需要关掉「自动设定时区」再手动选城市。iOS 不允许电脑直接改设备时区，所以 Elsewhere 只做检查和提醒。

**改定位失败？**
面板里会显示原因和原始报错，可以直接拷贝。常见原因：

- 手机锁屏了：解锁后再试
- 开发者模式没开，或者开了还没重启
- 信任失效：在 iPhone 上「设置 › 开发者 › 清除受信任的电脑」，然后重新连接、重新信任
- 开发者组件下载失败：检查网络后重试；也可以在「设置 › 定位方式」里换成另一种
- 拔线后找不到设备：插线点一次「允许无线连接」；确认设备和 Mac 在同一个 Wi-Fi 上；在设备上关闭这个网络的「私有无线局域网地址」
- 装了多个 Xcode：执行 `xcode-select -p` 确认路径对不对

**出口 IP 查不到？**
出口位置来自 [ipinfo.io](https://ipinfo.io)，后台检测出口变化用的是 [ipify](https://www.ipify.org)，两个都走系统代理。检查代理是否通，或者检查分流规则是否把这两个域名放行了。

**搜索海外地名不准？**
联想列表里带地球图标的是 OpenStreetMap 结果，带地图图标的是 Apple 地图结果。中文的海外地名直接按回车，会用 OpenStreetMap 的 Nominatim 精确搜索。输入框里也可以直接粘贴坐标，比如 `35.6586, 139.7454`。

**搜索会把什么发出去？**
你输入的搜索词会发给 Apple 地图和 OpenStreetMap（[Photon](https://photon.komoot.io) 和 [Nominatim](https://nominatim.openstreetmap.org)），用来查地点。除此之外不上传任何东西，也没有统计。

**出口跟的是 Mac 还是手机？**
默认按这台 Mac 的网络查。手机用的是另一个代理（比如 Mac 上 Surge、手机上小火箭）时，两边出口可能不同。这时在「设置 › 出口来源」选「手机」，并在手机的代理 App 里打开代理共享（各 App 叫法不同，比如「代理共享」「允许 Wi-Fi 访问」），把它显示的局域网地址和端口（如 `192.168.1.20:1082`）填进去。Elsewhere 会经这个代理查出口，查到的就是手机的出口。手机和 Mac 需要在同一个 Wi-Fi 上。第一次使用时 macOS 会询问是否允许 Elsewhere 访问本地网络，需要点「允许」（之后可在「系统设置 › 隐私与安全性 › 本地网络」里修改）。

**快捷指令怎么用？**
打开「快捷指令」App，搜索 Elsewhere，就能看到四个动作，也可以直接用「用 Elsewhere 跟随代理出口」这类现成的短语。动作会作用于 Elsewhere 当前选中的设备（打开「同时修改所有设备」时是全部）。

**「自动改」为什么没生效？**
只有当前定位来自「跟随代理出口」时才会自动改，这样不会覆盖你手动选的城市。

**在国内地图上选的点会不会偏？**
不会。大陆地区的 Apple 地图用的是 GCJ-02（火星坐标），Elsewhere 应用前会自动转成 GPS 用的 WGS-84。港澳台和海外坐标不做转换。

**有多台 iPhone / iPad 连着？**
面板顶部会出现切换按钮。

## 和其他方案的区别

| 方案 | 原理 | 需要 | 现状 |
| --- | --- | --- | --- |
| **Elsewhere** | 开发者服务的模拟定位（内置组件或 Xcode） | Mac + 开发者模式 | 可用，重启后失效 |
| Roam Control / WrapPin | 手机端配对后走同一条开发者通道 | 侧载 App、开发者模式 | 可脱离电脑，侧载需要定期续签 |
| WLOC 类 Surge 模块 | MITM 改写 Apple Wi-Fi 定位服务的返回结果 | 信任 MITM 根证书 | 据报 iOS 27 起失效，只影响网络定位 |
| 定位尾插 | 外置 GPS 配件（推测） | 专用硬件 | 不依赖电脑 |

## 项目结构

```
helper/                         内置组件 elsewhere-helper（Rust，基于 idevice）
Elsewhere/
├── ElsewhereApp.swift          菜单栏入口
├── AppModel.swift              状态、轮询、改定位逻辑
├── Models.swift                城市、定位记录等数据结构
├── Services/
│   ├── DeviceService.swift     Xcode 方式：xcrun devicectl 封装、设备识别
│   ├── HelperEngine.swift      内置方式：调用 elsewhere-helper，下载开发者组件
│   ├── ExitIPService.swift     出口 IP 查询
│   ├── ChinaCoordinate.swift   GCJ-02 ↔ WGS-84
│   ├── HotKey.swift            全局快捷键
│   ├── Notifier.swift          系统通知
│   └── Shell.swift             Process 封装
└── Views/
    ├── PanelView.swift         菜单栏面板（快捷操作）
    ├── MainWindow.swift        主窗口：侧边栏和各栏目
    ├── MapWindow.swift         地图
    ├── CodeField.swift         会动的字符场背景
    ├── PlaceSearch.swift       Apple 地图 + OpenStreetMap 地名搜索
    ├── Splash.swift            第一次打开时盖在主窗口上的开场页
    ├── WordmarkGlyphs.swift    ELSEWHERE 字标的字形
    └── ...                     常用城市、设置等
```

开发小技巧：`open Elsewhere.app --args -showPanelWindow YES` 会把面板放在普通窗口里显示，方便截图和调试。可以再加 `-panelPage cities`（或 `settings`）直接打开对应页面，`-showMainWindow location`（或 `map`、`cities`、`device`、`settings`）直接打开主窗口的对应栏目，`-panelAppearance dark` 用深色显示。`-showSplash YES` 每次都显示开场页，`-splashAppearance dark` 用深色显示，`-splashDemo YES` 在开场页上自动点一下、拖一段（截图看波纹用），`-alwaysAnimate YES` 窗口不在前台时字符场也接着动。调试版还可以加 `-demo YES`：换成一台假的 iPhone 和假的出口（文档用 IP），不碰真设备、不保存设置，用来截宣传图。

## 免责声明

本工具只调用 Apple 官方开发者工具，请在遵守当地法律和各 App 服务条款的前提下使用。修改定位可能影响依赖位置的功能（比如查找、天气、打车等），用完记得恢复真实定位。

## License

[MIT](LICENSE)

ELSEWHERE 字标的字形取自 [Jost](https://github.com/indestructible-type/Jost)（Light），按 [SIL Open Font License 1.1](Licenses/Jost-OFL.txt) 使用。
