# Logi Battery (menu bar)

A tiny macOS menu bar app that shows the battery level of your Logitech keyboard and mouse, for example:

```
⌨ 100%   🖱 50%
```

- Shows each connected Logitech device with its battery percentage
- Turns orange at 30% and red at 15%; shows ⚡︎ while charging
- Click it for a per-device list, **Refresh Now** (⌘R), **Open at Login** and **Quit**
- Refreshes every 2 minutes and after your Mac wakes
- No Dock icon, no network access, about 6 KB of Swift

Tested with an **MX Keys S** and **MX Master 3S** on a **Logi Bolt** receiver. It should work with most
recent Logitech devices that support HID++ 2.0, over a Bolt or Unifying receiver or Bluetooth.

## How it works

Logi Options+ doesn't save live battery levels anywhere other apps can read, and its background
service doesn't accept outside connections. So this app asks the devices directly, using
Logitech's HID++ 2.0 protocol over the receiver (the same messages Options+ sends):

1. Finds Logitech HID++ interfaces (vendor ID `0x046D`, usage page `0xFF00`) with IOKit
2. Pings each paired device slot to wake it
3. Reads the `UNIFIED_BATTERY` (`0x1004`) status, falling back to `BATTERY_STATUS` (`0x1000`)
4. Accepts a reading only when two reads in a row agree, to avoid bad values from sleeping devices

It runs fine alongside Logi Options+; you don't need Options+ installed at all.

## Install

### Download

1. Download `Logi-Battery.zip` from the [latest release](../../releases/latest) and unzip it
2. Move **Logi Battery.app** to your Applications folder
3. The app isn't notarized by Apple, so the first time, **right-click it → Open → Open**
   (or run `xattr -dr com.apple.quarantine "/Applications/Logi Battery.app"`)
4. It turns on **Open at Login** automatically the first time it runs (you can switch it off in its menu).
   If macOS asks, allow it under **System Settings → General → Login Items & Extensions**

### Build from source

Requires macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/wasimahmed19/logi-battery-menubar.git
cd logi-battery-menubar
./build.sh
open "Logi Battery.app"
```

## Troubleshooting

- **Shows "Logi –"**: no device answered. Move the mouse or press a key to wake it, then choose **Refresh Now**.
- **A device is missing**: it may not support HID++ 2.0 battery reporting, or it's connected in a way
  the app doesn't scan yet. Run with debug output and open an issue with the log:
  ```bash
  LOGI_DEBUG=1 "/Applications/Logi Battery.app/Contents/MacOS/LogiBattery"
  ```

## Files

- `HIDPP.swift`: HID++ communication and device scanning
- `main.swift`: the menu bar app
- `build.sh`: compiles and packages `Logi Battery.app`

## License

[MIT](LICENSE). Not affiliated with or endorsed by Logitech. Logitech, Logi, MX Keys and MX Master
are trademarks of Logitech.
