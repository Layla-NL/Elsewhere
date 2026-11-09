# Elsewhere

一个 macOS 菜单栏小工具：一键把 iPhone 的定位改到代理出口所在的城市，或者任意你想去的地方。

> Elsewhere is a tiny macOS menu-bar app that changes a connected iPhone's location — to your proxy's exit IP, a favorite city, or any spot on the map — using Xcode's own `devicectl`. No jailbreak, no profiles, nothing installed on the phone.

- **跟随代理出口**：查当前出口 IP 的位置（走系统代理，和 Surge 等工具一致），一键把定位改过去
- **出口变化提醒 / 自动跟随**：在 Surge 里换了节点，自动发现并提醒，或者直接跟着改
- **常用城市**：内置 11 个城市，可以增删、拖动排序
- **地图窗口**：大地图上点一下就能选点，也可以搜地名或输入坐标；地图上同时标出 iPhone 当前位置和代理出口，选好后一键「应用到 iPhone」（⌘↩），也能直接恢复真实定位
- **海外地名也搜得到**：国区 Mac 的 Apple 地图用的是高德数据，海外地名基本搜不出来。Elsewhere 同时用 OpenStreetMap 搜索：边输入边联想，回车精确搜索，「东京塔」「埃菲尔铁塔」这样的中文名也能找到
- **恢复真实定位**：一个按钮
- **自动识别 iPhone**：插线自动识别，连不上时告诉你原因（没插线、没信任、没开开发者模式）
- **全局快捷键** `⌃⌥⌘L`：随时跟随出口，结果用系统通知告诉你
- 开机自启、深浅色模式、中文界面

## 原理

调用 Xcode 自带的 `xcrun devicectl device simulate location`，也就是 Xcode 调试时用的「模拟定位」。

- 不越狱、不装描述文件或根证书，手机上不装任何 App
- 对所有 App 和系统服务生效
- 拔线后定位仍然保持；**iPhone 重启后会恢复真实定位**，需要重新连线再改一次

## 系统要求

- macOS 14 或更新版本
- 已安装 Xcode（需要 `xcrun devicectl`，Xcode 15 及以上自带）
- iPhone 打开开发者模式

## 编译和安装

**用 Xcode：** 打开 `Elsewhere.xcodeproj`，按 ⌘R 运行。

**用命令行：**

```bash
scripts/build.sh --install
```

编译 Release 版，复制到 `/Applications/Elsewhere.app` 并打开。App 没有沙盒（要调用 `xcrun`），用的是本机 ad-hoc 签名，不需要开发者账号。

如果用的是别人编译好的 `Elsewhere.app`，第一次打开可能被 Gatekeeper 拦住。在 Finder 里右键点「打开」，或者执行：

```bash
xattr -dr com.apple.quarantine /Applications/Elsewhere.app
```

## 首次使用

1. **连接并信任**：用数据线把 iPhone 连到 Mac，解锁手机，在弹窗里点「信任」并输入锁屏密码。
2. **打开开发者模式**：iPhone 上进入「设置 › 隐私与安全性 › 开发者模式」，打开后按提示重启手机。如果找不到这个选项，先打开一次 Xcode 并连上手机，选项就会出现。
3. **允许通知**（可选）：第一次启动时允许通知。快捷键和自动跟随的结果，以及「出口变了」的提醒，都靠系统通知发出。
4. 点菜单栏的定位图标，看到「已连接」就可以用了。

第一次改定位时，Xcode 可能要往手机上挂载开发者磁盘映像，会多花几秒钟。

## 常见问题

**手机重启后定位变回来了？**
这是正常现象：模拟定位只在本次开机内有效。重新连线后再点一次就好。

**提示「改定位失败」？**
面板里会显示 `devicectl` 的原始报错，可以直接拷贝。常见原因：

- 手机锁屏了：解锁后再试
- 开发者模式没开，或者开了还没重启
- 信任失效：在 iPhone 上「设置 › 开发者 › 清除受信任的电脑」，然后重新连接、重新信任
- 装了多个 Xcode：执行 `xcode-select -p` 确认路径对不对

**出口 IP 查不到？**
出口位置来自 [ipinfo.io](https://ipinfo.io)，后台检测出口变化用的是 [ipify](https://www.ipify.org)，两个都走系统代理。检查代理是否通，或者检查分流规则是否把这两个域名放行了。

**搜索海外地名不准？**
联想列表里带地球图标的是 OpenStreetMap 结果，带地图图标的是 Apple 地图结果。中文的海外地名直接按回车，会用 OpenStreetMap 的 Nominatim 精确搜索。输入框里也可以直接粘贴坐标，比如 `35.6586, 139.7454`。

**搜索会把什么发出去？**
你输入的搜索词会发给 Apple 地图和 OpenStreetMap（[Photon](https://photon.komoot.io) 和 [Nominatim](https://nominatim.openstreetmap.org)），用来查地点。除此之外不上传任何东西，也没有统计。

**「自动改」为什么没生效？**
只有当前定位来自「跟随代理出口」时才会自动改，这样不会覆盖你手动选的城市。

**在国内地图上选的点会不会偏？**
不会。大陆地区的 Apple 地图用的是 GCJ-02（火星坐标），Elsewhere 应用前会自动转成 GPS 用的 WGS-84。港澳台和海外坐标不做转换。

**有多台 iPhone / iPad 连着？**
面板顶部会出现切换按钮。

## 和其他方案的区别

| 方案 | 原理 | 需要 | 现状 |
| --- | --- | --- | --- |
| **Elsewhere** | Xcode `devicectl` 模拟定位 | Mac + Xcode + 开发者模式 | 可用，重启后失效 |
| Roam Control / WrapPin | 手机端配对后走同一条开发者通道 | 侧载 App、开发者模式 | 可脱离电脑，侧载需要定期续签 |
| WLOC 类 Surge 模块 | MITM 改写 Apple Wi-Fi 定位服务的返回结果 | 信任 MITM 根证书 | 据报 iOS 27 起失效，只影响网络定位 |
| 定位尾插 | 外置 GPS 配件（推测） | 专用硬件 | 不依赖电脑 |

## 项目结构

```
Elsewhere/
├── ElsewhereApp.swift          菜单栏入口
├── AppModel.swift              状态、轮询、改定位逻辑
├── Models.swift                城市、定位记录等数据结构
├── Services/
│   ├── DeviceService.swift     xcrun devicectl 封装、设备识别
│   ├── ExitIPService.swift     出口 IP 查询
│   ├── ChinaCoordinate.swift   GCJ-02 ↔ WGS-84
│   ├── HotKey.swift            全局快捷键
│   ├── Notifier.swift          系统通知
│   └── Shell.swift             Process 封装
└── Views/
    ├── PanelView.swift         菜单栏面板
    ├── MapWindow.swift         地图窗口
    ├── PlaceSearch.swift       Apple 地图 + OpenStreetMap 地名搜索
    └── ...                     常用城市、设置等
```

开发小技巧：`open Elsewhere.app --args -showPanelWindow YES` 会把面板放在普通窗口里显示，方便截图和调试。可以再加 `-panelPage cities`（或 `settings`）直接打开对应页面，`-panelPage map` 会打开地图窗口。

## 免责声明

本工具只调用 Apple 官方开发者工具，请在遵守当地法律和各 App 服务条款的前提下使用。修改定位可能影响依赖位置的功能（比如查找、天气、打车等），用完记得恢复真实定位。

## License

[MIT](LICENSE)
