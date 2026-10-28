# router-speed

Live WAN upload/download rates and totals from a home router via UPnP IGD. No admin login.

Default control URL: `http://192.168.0.1:1900/ifc` (tested on TP-Link XDR5430). Change it for another router.

## CLI

```bash
python3 router_speed.py
```

```bash
cmake -S . -B build && cmake --build build
./build/router_speed
```

## macOS menu bar (AppKit, recommended)

```bash
cd RouterSpeedBar
./make-app.sh
open RouterSpeedBar.app
```

`RouterSpeedBarUI` is a SwiftUI counterpart; the menu-bar label is still a two-line image. Do not run both at once.
