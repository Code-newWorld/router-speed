#!/usr/bin/env python3
"""Live WAN rate + totals from the home router via UPnP IGD (no admin login)."""

from __future__ import annotations

import argparse
import re
import sys
import time
import urllib.error
import urllib.request

IFC_NS = "urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1"
DEFAULT_CONTROL = "http://192.168.0.1:1900/ifc"


def soap(url: str, action: str, timeout: float) -> str:
    body = (
        '<?xml version="1.0"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        "<s:Body>"
        f'<u:{action} xmlns:u="{IFC_NS}"></u:{action}>'
        "</s:Body></s:Envelope>"
    ).encode()
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": 'text/xml; charset="utf-8"',
            "SOAPAction": f'"{IFC_NS}#{action}"',
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", "replace")


def xml_int(xml: str, tag: str) -> int:
    match = re.search(rf"<{tag}[^>]*>([^<]+)", xml)
    if not match:
        raise ValueError(f"missing <{tag}>")
    return int(match.group(1))


def read_totals(url: str, timeout: float) -> tuple[int, int]:
    sent = xml_int(soap(url, "GetTotalBytesSent", timeout), "NewTotalBytesSent")
    recv = xml_int(soap(url, "GetTotalBytesReceived", timeout), "NewTotalBytesReceived")
    return sent, recv


def unwrap(prev: int, cur: int) -> int:
    """Positive delta, including 32-bit counter wrap."""
    if cur >= prev:
        return cur - prev
    for bits in (32, 64):
        if prev < (1 << bits):
            return cur + (1 << bits) - prev
    return cur


def fmt_bytes(n: int) -> str:
    value = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(value) < 1024 or unit == "TB":
            if unit == "B":
                return f"{int(value)} {unit}"
            return f"{value:.2f} {unit}"
        value /= 1024
    return f"{n} B"


def fmt_rate(bytes_per_sec: float) -> str:
    if bytes_per_sec < 0:
        bytes_per_sec = 0
    value = float(bytes_per_sec)
    for unit in ("B/s", "KB/s", "MB/s", "GB/s"):
        if value < 1024 or unit == "GB/s":
            if unit == "B/s":
                return f"{int(value)} {unit}"
            return f"{value:.2f} {unit}"
        value /= 1024
    return f"{bytes_per_sec:.2f} B/s"


def main() -> int:
    parser = argparse.ArgumentParser(description="Router WAN speed via UPnP IGD")
    parser.add_argument("--url", default=DEFAULT_CONTROL, help="WANCommonInterfaceConfig control URL")
    parser.add_argument("--interval", type=float, default=1.0, help="refresh seconds")
    parser.add_argument("--timeout", type=float, default=4.0)
    args = parser.parse_args()
    if args.interval < 0.3:
        args.interval = 0.3

    try:
        prev_sent, prev_recv = read_totals(args.url, args.timeout)
    except (urllib.error.URLError, TimeoutError, ValueError, OSError) as exc:
        print(f"连不上路由器 UPnP：{exc}", file=sys.stderr)
        print(f"控制地址：{args.url}", file=sys.stderr)
        return 1

    prev_t = time.monotonic()
    print("来源：UPnP IGD 累计字节（不登录网页）")
    print("Ctrl+C 退出\n")

    try:
        while True:
            time.sleep(args.interval)
            try:
                sent, recv = read_totals(args.url, args.timeout)
            except (urllib.error.URLError, TimeoutError, ValueError, OSError) as exc:
                print(f"\r读取失败：{exc}          ", flush=True)
                continue
            now = time.monotonic()
            dt = now - prev_t
            if dt <= 0:
                continue
            up = unwrap(prev_sent, sent) / dt
            down = unwrap(prev_recv, recv) / dt
            prev_sent, prev_recv, prev_t = sent, recv, now

            # ANSI clear-home so the block stays in place
            sys.stdout.write("\x1b[H\x1b[J")
            print("路由器 WAN")
            print(f"  上传  {fmt_rate(up):>12}    累计  {fmt_bytes(sent)}")
            print(f"  下载  {fmt_rate(down):>12}    累计  {fmt_bytes(recv)}")
            print(f"\n间隔 {dt:.2f}s   {args.url}")
            sys.stdout.flush()
    except KeyboardInterrupt:
        print("\n已退出")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
