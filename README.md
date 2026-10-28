# router-speed

从家用路由器（UPnP IGD）读 WAN 实时上传/下载速度和累计流量，不登录管理页面。

默认控制地址是 `http://192.168.0.1:1900/ifc`（TP-Link XDR5430 易展版上测过）。换路由器时改这个 URL。

## 命令行

```bash
python3 router_speed.py
```

```bash
cmake -S . -B build && cmake --build build
./build/router_speed
```

## macOS 菜单栏（推荐 AppKit 版）

```bash
cd RouterSpeedBar
./make-app.sh
open RouterSpeedBar.app
```

`RouterSpeedBarUI` 是 SwiftUI 对照实验，顶栏同样用两行图绘制。不要两份一起开。
