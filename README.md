# Elsewhere

**English** | [简体中文](README.zh-CN.md)

A tiny macOS menu-bar app that changes a connected iPhone's or iPad's location in one click: to the city your proxy exits from, a favorite city, or any spot on the map.

It talks to the device through a built-in helper (based on [idevice](https://github.com/jkcoxson/idevice)), so Xcode is not required. No jailbreak, no profiles, nothing installed on the phone.

- **Follow Proxy Exit**: looks up where your current exit IP is and moves the location there. The exit can be checked through this Mac (via the system proxy, same as Surge and similar tools) or through the phone (via the proxy app's "proxy sharing")
- **Exit change alerts / auto-follow**: switch servers in Surge and Elsewhere notices, then notifies you or moves the location along with it
- **Favorites**: 11 built-in cities; add, remove and drag to reorder
- **Main window**: a sidebar with Location, Map, Favorites, Device and Settings over an animated character field. The menu-bar panel keeps the everyday actions; Open Elsewhere takes you to the main window
- **Map**: click anywhere on a big map to drop a pin, or search places and enter coordinates. The map shows both the iPhone's current spot and the proxy exit; Apply to iPhone (⌘↩) when you're happy, or go straight back to the real location
- **Finds places abroad**: on Macs set to the China region, Apple Maps uses AutoNavi data and barely finds anything overseas. Elsewhere also searches OpenStreetMap, with suggestions as you type and an exact search on Return. Chinese names such as 东京塔 or 埃菲尔铁塔 work too
- **Use Real Location**: one button
- **Restores after a restart**: restarting the device drops the simulated location; when it reconnects, Elsewhere moves it back to the last spot (can be turned off in Settings)
- **Time zone check**: warns when the device's time zone doesn't match its location, with steps for that device
- **Shortcuts**: Follow Proxy Exit, Move to Favorite City, Move to Coordinates and Use Real Location are available in the Shortcuts app
- **Several devices**: change every connected iPhone and iPad at once
- **No Xcode needed**: the connection helper is built in, so it works right after download, over a cable or wirelessly
- **Detects iPhone and iPad automatically**: plug in and it shows up; if it can't connect, it tells you why (not plugged in, not trusted, Developer Mode off)
- **Global shortcut** `⌃⌥⌘L`: follow the exit any time, with the result as a notification
- **Just location, if you like**: turn off Settings › Proxy exit features to stop looking up the exit IP and hide Follow Exit, exit alerts and the shortcut
- Opens at login, light and dark mode
- **English and Simplified Chinese**: follows the system language (other languages show English)

## How it works

It uses the same "simulate location" that Xcode uses while debugging: the location simulation in iOS developer services, the same interface as `xcrun devicectl device simulate location`.

- No jailbreak, no profiles or root certificates, no app on the phone
- Applies to every app and system service
- The location stays after you unplug; **restarting the device brings back the real location**, so connect again and re-apply

Elsewhere has two engines, chosen in Settings › Location engine (default: Automatic):

| Engine | How it connects | Needs |
| --- | --- | --- |
| **Built-in** | The bundled `elsewhere-helper` (based on the open-source [idevice](https://github.com/jkcoxson/idevice)), through macOS's own usbmuxd | A cable, or wireless connection turned on |
| **Xcode** | Xcode's `devicectl` | Xcode installed |

Automatic prefers the built-in engine. Devices that only Xcode can reach (for example ones paired with Xcode wirelessly) go to Xcode, and if the built-in engine fails it retries with Xcode.

**Wireless connection**: with the device plugged in, click Allow Wireless Connection in the panel (the same as Finder's "Show this iPhone when on Wi-Fi"). After that, as long as the device and the Mac are on the same Wi-Fi, you can change the location without the cable.

You also need to turn off Private Wi-Fi Address for that network on the device (Settings › Wi-Fi, tap ⓘ next to the network). macOS recognizes the device by its Wi-Fi address; a private address differs from the one recorded at pairing, so the Mac won't recognize the device.

**Developer disk image**: since iOS 17, Apple's developer disk image has to be mounted on the device before the location can change. With Xcode installed it's usually mounted for you. If not, Elsewhere prepares one the first time it's needed: it uses the iOS developer disk image already on the Mac from Xcode or the system (`/Library/Developer/DeveloperDiskImages`), or otherwise downloads one (about 17 MB, from [a mirror of Apple's images](https://github.com/doronz88/DeveloperDiskImage), the same one pymobiledevice3 uses), checks that the image matches its manifest, and caches it in `~/Library/Application Support/Elsewhere`. When mounting, it asks Apple online for a signature for that specific device; devices only accept images Apple has signed.

## Requirements

- macOS 14 or later
- iPhone or iPad on iOS 17 or later, with Developer Mode on
- Xcode is optional

## Download

Get `Elsewhere-x.y.z.zip` from [Releases](https://github.com/Layla-NL/Elsewhere/releases/latest), unzip it and drag `Elsewhere.app` into Applications. Releases are signed with Developer ID and notarized by Apple, so they open with a double-click.

## Build and install

**With Xcode:** open `Elsewhere.xcodeproj` and press ⌘R.

**From the command line:**

```bash
scripts/build.sh --install
```

This builds Release, copies it to `/Applications/Elsewhere.app` and opens it. The app isn't sandboxed (it runs the helper and `xcrun`) and uses a local ad-hoc signature, so no developer account is needed.

Building the helper needs Rust: `brew install rust` (or use [rustup](https://rustup.rs)). The Xcode build compiles `helper/` with cargo and puts it in `Elsewhere.app/Contents/Helpers`.

For a release build, run `TEAM_ID=YOUR_TEAM_ID scripts/release.sh`: it signs with Developer ID, notarizes and produces a zip ready to distribute.

If you're using an `Elsewhere.app` someone else built, Gatekeeper may block it the first time. Right-click it in Finder and choose Open, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Elsewhere.app
```

## First run

1. **Connect and trust**: connect the iPhone to the Mac with a cable, unlock it, tap Trust and enter the passcode.
2. **Turn on Developer Mode**: on the iPhone, go to Settings › Privacy & Security › Developer Mode, turn it on and restart when asked. If the option isn't there, connect once with Elsewhere (or open Xcode once with the phone connected) and it will appear.
3. **Allow notifications** (optional): allow them on first launch. Results from the shortcut and auto-follow, and "Proxy exit changed" alerts, arrive as notifications.
4. Click the location icon in the menu bar. Once it says Connected, you're ready.

The first location change may take longer while the developer disk image is prepared (downloaded and mounted).

## FAQ

**The iPad stays at the simulated location after I restore the real one?**
Wi-Fi iPads have no GPS. After simulation ends they work out their position from nearby Wi-Fi, and until then they keep showing the last location. Wait a bit, or toggle Settings › Privacy & Security › Location Services off and on. iPhones with GPS usually come back within seconds.

**The location went back after the phone restarted?**
A simulated location only lasts until the device restarts. While Elsewhere is running, it moves the device back to the last spot when it reconnects (Settings › Restore location after reconnecting); if the device just booted and is still locked, that happens after you unlock it. To go back to the real location, click Use Real Location.

**Why doesn't the time zone match the location?**
With iOS's Set Automatically for time zone, devices without cellular (such as Wi-Fi iPads) follow the location, so just turn it on. iPhones with a SIM follow the carrier network instead of the simulated location, so turn Set Automatically off and pick a city by hand. iOS doesn't let a computer change a device's time zone, so Elsewhere only checks and reminds you.

**Changing the location failed?**
The panel shows the reason and the raw error, which you can copy. Common causes:

- The phone is locked: unlock it and try again
- Developer Mode is off, or was turned on without restarting
- Trust is broken: on the iPhone, go to Settings › Developer › Clear Trusted Computers, then reconnect and trust again
- The developer disk image failed to download: check the network and try again, or switch engines in Settings › Location engine
- The device isn't found after unplugging: plug in and click Allow Wireless Connection once; make sure the device and Mac share a Wi-Fi network; turn off Private Wi-Fi Address for that network on the device
- Several Xcode versions installed: run `xcode-select -p` to check the path

**The exit IP can't be found?**
The exit location comes from [ipinfo.io](https://ipinfo.io), and background change detection uses [ipify](https://www.ipify.org); both go through the system proxy. Check that the proxy works and that your rules let these two domains through.

**Searching for places abroad is inaccurate?**
In the suggestions, results with a globe icon come from OpenStreetMap and ones with a map icon from Apple Maps. Press Return to run an exact search with OpenStreetMap's Nominatim. You can also paste coordinates into the search field, for example `35.6586, 139.7454`.

**What does search send out?**
What you type is sent to Apple Maps and OpenStreetMap ([Photon](https://photon.komoot.io) and [Nominatim](https://nominatim.openstreetmap.org)) to look up places. Nothing else is uploaded, and there are no analytics.

**Does the exit follow the Mac or the phone?**
By default it's checked through this Mac's network. If the phone uses a different proxy (say Surge on the Mac and Shadowrocket on the phone), the two exits can differ. In that case choose Phone under Settings › Exit source, turn on proxy sharing in the phone's proxy app (each app names it differently, e.g. "Proxy Sharing" or "Allow Wi-Fi Access") and enter the LAN address and port it shows (such as `192.168.1.20:1082`). Elsewhere then looks up the exit through that proxy, which gives you the phone's exit. The phone and Mac must be on the same Wi-Fi. The first time, macOS asks whether Elsewhere may access the local network; click Allow (you can change it later in System Settings › Privacy & Security › Local Network).

**How do I use Shortcuts?**
Open the Shortcuts app and search for Elsewhere to find the four actions, or use ready-made phrases such as "Follow proxy exit with Elsewhere". Actions apply to the device currently selected in Elsewhere (or all devices when Change all devices at once is on).

**Why didn't Auto Move kick in?**
It only moves automatically when the current location came from Follow Proxy Exit, so it never overrides a city you picked yourself.

**Will a point picked on a map of mainland China be off?**
No. Apple Maps uses GCJ-02 in mainland China; Elsewhere converts to the WGS-84 coordinates GPS uses before applying. Hong Kong, Macau, Taiwan and everywhere else are left as is.

**Several iPhones or iPads connected?**
A switch button appears at the top of the panel.

## How it compares

| Approach | How it works | Needs | Status |
| --- | --- | --- | --- |
| **Elsewhere** | Developer-services location simulation (built-in helper or Xcode) | A Mac + Developer Mode | Works; resets on restart |
| Roam Control / WrapPin | Pairs on the phone and uses the same developer channel | Sideloaded app, Developer Mode | Works without a computer; sideloading needs periodic re-signing |
| WLOC-style Surge modules | MITM-rewrite Apple's Wi-Fi location service responses | Trusting a MITM root certificate | Reportedly broken since iOS 27; only affects network location |
| Lightning/USB-C GPS dongles | External GPS accessory (presumably) | Dedicated hardware | No computer needed |

## Project layout

```
helper/                         Built-in helper elsewhere-helper (Rust, based on idevice)
Elsewhere/
├── ElsewhereApp.swift          Menu-bar entry point
├── AppModel.swift              State, polling, location logic
├── Models.swift                Cities, location records and other data types
├── Localizable.xcstrings       UI text in English and Simplified Chinese
├── Services/
│   ├── DeviceService.swift     Xcode engine: xcrun devicectl wrapper, device detection
│   ├── HelperEngine.swift      Built-in engine: runs elsewhere-helper, prepares the disk image
│   ├── ExitIPService.swift     Exit IP lookup
│   ├── ChinaCoordinate.swift   GCJ-02 ↔ WGS-84
│   ├── HotKey.swift            Global shortcut
│   ├── Notifier.swift          Notifications
│   └── Shell.swift             Process wrapper
└── Views/
    ├── PanelView.swift         Menu-bar panel (quick actions)
    ├── MainWindow.swift        Main window: sidebar and sections
    ├── MapWindow.swift         Map
    ├── CodeField.swift         Animated character-field background
    ├── PlaceSearch.swift       Apple Maps + OpenStreetMap place search
    ├── Splash.swift            Intro screen shown over the main window on first launch
    ├── WordmarkGlyphs.swift    Glyphs for the ELSEWHERE wordmark
    └── ...                     Favorites, Settings and more
```

Development tips: `open Elsewhere.app --args -showPanelWindow YES` shows the panel in a regular window for screenshots and debugging. Add `-panelPage cities` (or `settings`) to open that page, `-showMainWindow location` (or `map`, `cities`, `device`, `settings`) to open a main-window section, and `-panelAppearance dark` for dark mode. `-showSplash YES` always shows the intro, `-splashAppearance dark` shows it dark, `-splashDemo YES` clicks and drags on it automatically (for capturing the ripples), and `-alwaysAnimate YES` keeps the character field moving when the window isn't in front. Debug builds also accept `-demo YES`, which swaps in a fake iPhone and a fake exit (a documentation IP), never touches real devices and saves no settings; it's for promo screenshots. Add `-AppleLanguages "(en)"` or `"(zh-Hans)"` to switch the UI language.

**UI text**: strings are written in Chinese in the code (`Text("设置")`, `String(localized: "已连接")`), and the Chinese text is the key. Translations live in `Elsewhere/Localizable.xcstrings` (plus `AppShortcuts.xcstrings` for Shortcuts phrases and `InfoPlist.xcstrings` for the permission prompt). When you add text, fill in both `en` and `zh-Hans` there.

## Disclaimer

Elsewhere only uses Apple's official developer tooling. Use it in line with local law and each app's terms of service. Changing the location can affect location-based features (Find My, Weather, ride-hailing and so on), so remember to switch back to your real location when you're done.

## License

[MIT](LICENSE)

The ELSEWHERE wordmark glyphs come from [Jost](https://github.com/indestructible-type/Jost) (Light), used under the [SIL Open Font License 1.1](Licenses/Jost-OFL.txt).
