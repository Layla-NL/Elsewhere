//! elsewhere-helper: the part of Elsewhere that talks to an iPhone or iPad
//! without Xcode, through macOS's own usbmuxd and the `idevice` crate.
//!
//!   elsewhere-helper list
//!   elsewhere-helper set <udid> <latitude> <longitude> --ddi <dir>
//!   elsewhere-helper clear <udid>
//!   elsewhere-helper wifi <udid> on|off
//!
//! Every command prints one JSON object on stdout and exits 0, even on
//! failure, so the app can read `ok`, `code` and `error` the same way.
//! `--ddi <dir>` holds BuildManifest.plist, Image.dmg and Image.dmg.trustcache,
//! used only when the device has no developer disk image mounted yet.

use std::{borrow::Cow, path::PathBuf};

use idevice::{
    IdeviceError, IdeviceService, ReadWrite, RsdService,
    core_device::CoreDeviceServiceClient,
    core_device_proxy::CoreDeviceProxy,
    lockdown::LockdownClient,
    mobile_image_mounter::ImageMounter,
    provider::{IdeviceProvider, UsbmuxdProvider},
    rsd::RsdHandshake,
    usbmuxd::{Connection, UsbmuxdAddr, UsbmuxdConnection},
};
use serde::Serialize;
use serde_json::{Value, json};

const LABEL: &str = "Elsewhere";
const SIMULATE_LOCATION: &str = "com.apple.coredevice.feature.simulatelocation";
const SET_LOCATION: &str = "com.apple.coredevice.action.setsimulatedlocation";
const CLEAR_LOCATION: &str = "com.apple.coredevice.action.clearsimulatedlocation";

/// A failure the app can act on: `code` picks the message, `error` is the detail.
struct Failure {
    code: &'static str,
    error: String,
}

impl Failure {
    fn new(code: &'static str, error: impl ToString) -> Self {
        Self { code, error: error.to_string() }
    }

    /// Sorts an idevice error into something the app can explain.
    fn from_idevice(context: &str, e: IdeviceError) -> Self {
        let code = match &e {
            IdeviceError::DeviceLocked => "locked",
            IdeviceError::InvalidHostID => "not_paired",
            IdeviceError::DeviceNotFound => "not_found",
            _ => "failed",
        };
        Self::new(code, format!("{context}: {e}"))
    }
}

type Outcome = Result<Value, Failure>;

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let outcome = run(&args).await;
    let output = match outcome {
        Ok(mut value) => {
            value["ok"] = json!(true);
            value
        }
        Err(f) => json!({ "ok": false, "code": f.code, "error": f.error }),
    };
    println!("{output}");
}

async fn run(args: &[String]) -> Outcome {
    match args.first().map(String::as_str) {
        Some("list") => list().await,
        Some("set") => {
            let udid = arg(args, 1, "udid")?;
            let latitude = number(args, 2, "latitude", 90.0)?;
            let longitude = number(args, 3, "longitude", 180.0)?;
            let ddi = flag(args, "--ddi").map(PathBuf::from);
            set(&udid, latitude, longitude, ddi).await
        }
        Some("clear") => clear(&arg(args, 1, "udid")?).await,
        Some("wifi") => {
            let udid = arg(args, 1, "udid")?;
            let on = match arg(args, 2, "on or off")?.as_str() {
                "on" => true,
                "off" => false,
                _ => return Err(Failure::new("usage", "wifi takes on or off")),
            };
            wifi(&udid, on).await
        }
        Some("version") => Ok(json!({ "version": env!("CARGO_PKG_VERSION") })),
        _ => Err(Failure::new("usage", "usage: elsewhere-helper list | set <udid> <lat> <lon> --ddi <dir> | clear <udid>")),
    }
}

fn arg(args: &[String], index: usize, name: &str) -> Result<String, Failure> {
    args.get(index)
        .filter(|a| !a.starts_with("--"))
        .cloned()
        .ok_or_else(|| Failure::new("usage", format!("missing {name}")))
}

fn number(args: &[String], index: usize, name: &str, limit: f64) -> Result<f64, Failure> {
    let value: f64 = arg(args, index, name)?
        .parse()
        .map_err(|_| Failure::new("usage", format!("{name} is not a number")))?;
    if !value.is_finite() || value.abs() > limit {
        return Err(Failure::new("usage", format!("{name} is out of range")));
    }
    Ok(value)
}

fn flag(args: &[String], name: &str) -> Option<String> {
    args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).cloned()
}

// MARK: Devices

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DeviceInfo {
    udid: String,
    name: Option<String>,
    device_class: Option<String>,
    product_type: Option<String>,
    os_version: Option<String>,
    /// "usb" or "network".
    connection: &'static str,
    /// The Mac has a pairing record, so the device trusts this Mac.
    paired: bool,
    /// None when the device would not say (for example, before trust).
    developer_mode: Option<bool>,
    /// Finder's "Show this iPhone when on Wi-Fi"; None before trust.
    wifi: Option<bool>,
    error: Option<String>,
}

async fn muxer() -> Result<UsbmuxdConnection, Failure> {
    UsbmuxdConnection::default()
        .await
        .map_err(|e| Failure::from_idevice("usbmuxd", e))
}

async fn list() -> Outcome {
    let mut mux = muxer().await?;
    let devices = mux.get_devices().await.map_err(|e| Failure::from_idevice("list devices", e))?;

    // A device can show up over both USB and Wi-Fi; keep one, USB first.
    let mut seen: Vec<(String, bool, idevice::usbmuxd::UsbmuxdDevice)> = Vec::new();
    for device in devices {
        let usb = matches!(device.connection_type, Connection::Usb);
        if let Some(existing) = seen.iter_mut().find(|(udid, _, _)| *udid == device.udid) {
            if usb && !existing.1 {
                *existing = (device.udid.clone(), usb, device);
            }
        } else {
            seen.push((device.udid.clone(), usb, device));
        }
    }

    let mut infos = Vec::new();
    for (udid, usb, device) in seen {
        let provider = device.to_provider(UsbmuxdAddr::default(), LABEL);
        let mut info = DeviceInfo {
            udid,
            name: None,
            device_class: None,
            product_type: None,
            os_version: None,
            connection: if usb { "usb" } else { "network" },
            paired: false,
            developer_mode: None,
            wifi: None,
            error: None,
        };
        if let Err(e) = describe(&provider, &mut info).await {
            info.error = Some(e.error);
        }
        infos.push(info);
    }
    Ok(json!({ "devices": infos }))
}

fn text(value: &plist::Value, key: &str) -> Option<String> {
    value.as_dictionary()?.get(key)?.as_string().map(str::to_string)
}

/// Fills in what lockdown will tell: a few values before trust, the rest after.
async fn describe(provider: &UsbmuxdProvider, info: &mut DeviceInfo) -> Result<(), Failure> {
    let mut lockdown = LockdownClient::connect(provider)
        .await
        .map_err(|e| Failure::from_idevice("lockdown", e))?;
    for (key, slot) in [
        ("ProductType", &mut info.product_type),
        ("DeviceClass", &mut info.device_class),
        ("ProductVersion", &mut info.os_version),
    ] {
        if let Ok(v) = lockdown.get_value(Some(key), None).await {
            *slot = v.as_string().map(str::to_string);
        }
    }

    let Ok(pairing) = provider.get_pairing_file().await else {
        return Ok(()); // Not trusted yet: no pairing record on this Mac.
    };
    if lockdown.start_session(&pairing).await.is_err() {
        return Ok(()); // The record is stale; the device needs to trust this Mac again.
    }
    info.paired = true;
    if let Ok(all) = lockdown.get_value(None, None).await {
        info.name = text(&all, "DeviceName");
        info.product_type = text(&all, "ProductType").or(info.product_type.take());
        info.device_class = text(&all, "DeviceClass").or(info.device_class.take());
        info.os_version = text(&all, "ProductVersion").or(info.os_version.take());
    }
    info.developer_mode = lockdown
        .get_value(Some("DeveloperModeStatus"), Some("com.apple.security.mac.amfi"))
        .await
        .ok()
        .and_then(|v| v.as_boolean());
    // Missing means it was never turned on.
    info.wifi = Some(
        lockdown
            .get_value(Some("EnableWifiConnections"), Some("com.apple.mobile.wireless_lockdown"))
            .await
            .ok()
            .and_then(|v| v.as_boolean())
            .unwrap_or(false),
    );
    Ok(())
}

async fn provider_for(udid: &str) -> Result<UsbmuxdProvider, Failure> {
    let mut mux = muxer().await?;
    let devices = mux.get_devices().await.map_err(|e| Failure::from_idevice("list devices", e))?;
    let device = devices
        .iter()
        .filter(|d| d.udid == udid)
        .min_by_key(|d| !matches!(d.connection_type, Connection::Usb))
        .ok_or_else(|| Failure::new("not_found", format!("{udid} is not connected")))?;
    Ok(device.to_provider(UsbmuxdAddr::default(), LABEL))
}

// MARK: Wi-Fi

/// The same switch as Finder's "Show this iPhone when on Wi-Fi". Once on, usbmuxd
/// also lists the device over the local network, so the cable can come off.
async fn wifi(udid: &str, on: bool) -> Outcome {
    let provider = provider_for(udid).await?;
    let mut lockdown = LockdownClient::connect(&provider)
        .await
        .map_err(|e| Failure::from_idevice("lockdown", e))?;
    let pairing = provider
        .get_pairing_file()
        .await
        .map_err(|e| Failure::from_idevice("pairing record", e))?;
    lockdown
        .start_session(&pairing)
        .await
        .map_err(|e| Failure::from_idevice("lockdown session", e))?;
    lockdown
        .set_value("EnableWifiConnections", on.into(), Some("com.apple.mobile.wireless_lockdown"))
        .await
        .map_err(|e| Failure::from_idevice("wifi connections", e))?;
    Ok(json!({ "wifi": on }))
}

// MARK: Developer disk image

async fn ddi_mounted(provider: &dyn IdeviceProvider) -> Result<bool, Failure> {
    let mut mounter = ImageMounter::connect(provider)
        .await
        .map_err(|e| Failure::from_idevice("image mounter", e))?;
    let images = mounter.copy_devices().await.map_err(|e| Failure::from_idevice("list images", e))?;
    Ok(!images.is_empty())
}

/// Mounts the personalized developer disk image; Apple signs it for this device online.
async fn mount_ddi(provider: &UsbmuxdProvider, dir: &PathBuf) -> Result<(), Failure> {
    let read = |name: &str| {
        let path = dir.join(name);
        async move {
            tokio::fs::read(&path)
                .await
                .map_err(|e| Failure::new("ddi_missing", format!("{}: {e}", path.display())))
        }
    };
    let manifest = read("BuildManifest.plist").await?;
    let image = read("Image.dmg").await?;
    let trust_cache = read("Image.dmg.trustcache").await?;

    let mut lockdown = LockdownClient::connect(provider)
        .await
        .map_err(|e| Failure::from_idevice("lockdown", e))?;
    let pairing = provider
        .get_pairing_file()
        .await
        .map_err(|e| Failure::from_idevice("pairing record", e))?;
    lockdown
        .start_session(&pairing)
        .await
        .map_err(|e| Failure::from_idevice("lockdown session", e))?;
    let chip_id = lockdown
        .get_value(Some("UniqueChipID"), None)
        .await
        .map_err(|e| Failure::from_idevice("chip id", e))?
        .as_unsigned_integer()
        .ok_or_else(|| Failure::new("failed", "no UniqueChipID"))?;

    let mut mounter = ImageMounter::connect(provider)
        .await
        .map_err(|e| Failure::from_idevice("image mounter", e))?;
    mounter
        .mount_personalized(provider, image, trust_cache, &manifest, None, chip_id)
        .await
        .map_err(|e| {
            let mut f = Failure::from_idevice("mount developer disk image", e);
            if f.code == "failed" {
                f.code = "ddi_mount";
            }
            f
        })
}

// MARK: Location

/// The CoreDevice location service, the one `devicectl device simulate location` uses.
/// What it sets stays after this program exits, until cleared or a restart.
struct LocationService(CoreDeviceServiceClient<Box<dyn ReadWrite>>);

impl RsdService for LocationService {
    fn rsd_service_name() -> Cow<'static, str> {
        Cow::Borrowed("com.apple.coredevice.locationservice")
    }

    async fn from_stream(stream: Box<dyn ReadWrite>) -> Result<Self, IdeviceError> {
        Ok(Self(CoreDeviceServiceClient::new(stream).await?))
    }
}

async fn location_action(provider: &UsbmuxdProvider, action: &str, input: plist::Dictionary) -> Result<(), Failure> {
    let proxy = CoreDeviceProxy::connect(provider)
        .await
        .map_err(|e| Failure::from_idevice("device tunnel", e))?;
    let rsd_port = proxy.tunnel_info().server_rsd_port;
    let mut adapter = proxy
        .create_software_tunnel()
        .map_err(|e| Failure::from_idevice("software tunnel", e))?
        .to_async_handle();
    let stream = adapter
        .connect(rsd_port)
        .await
        .map_err(|e| Failure::new("failed", format!("service discovery: {e}")))?;
    let mut handshake = RsdHandshake::new(stream)
        .await
        .map_err(|e| Failure::from_idevice("service discovery", e))?;
    let mut service = LocationService::connect_rsd(&mut adapter, &mut handshake)
        .await
        .map_err(|e| {
            let mut f = Failure::from_idevice("location service", e);
            if f.code == "failed" {
                f.code = "no_service"; // Usually: developer disk image not mounted.
            }
            f
        })?;
    service
        .0
        .invoke_with_plist_action(SIMULATE_LOCATION, input, action)
        .await
        .map(|_| ())
        .map_err(|e| Failure::from_idevice("simulate location", e))
}

async fn set(udid: &str, latitude: f64, longitude: f64, ddi: Option<PathBuf>) -> Outcome {
    let provider = provider_for(udid).await?;
    let mut mounted_now = false;
    if !ddi_mounted(&provider).await? {
        let dir = ddi.ok_or_else(|| Failure::new("ddi_missing", "no developer disk image directory given"))?;
        mount_ddi(&provider, &dir).await?;
        mounted_now = true;
    }
    let mut input = plist::Dictionary::new();
    input.insert("latitude".into(), latitude.into());
    input.insert("longitude".into(), longitude.into());
    location_action(&provider, SET_LOCATION, input).await?;
    Ok(json!({ "mountedDeveloperDiskImage": mounted_now }))
}

async fn clear(udid: &str) -> Outcome {
    let provider = provider_for(udid).await?;
    // Without the image nothing can be simulating, so there is nothing to clear.
    if !ddi_mounted(&provider).await? {
        return Ok(json!({ "cleared": false }));
    }
    location_action(&provider, CLEAR_LOCATION, plist::Dictionary::new()).await?;
    Ok(json!({ "cleared": true }))
}
