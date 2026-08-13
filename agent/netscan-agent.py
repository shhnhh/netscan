#!/usr/bin/env python3
"""
NetScan LAN agent.

Exposes the host OS's real ARP table over a tiny local HTTP API, so the
NetScan iOS app — sandboxed, and as of some iOS versions apparently blocked
from reading real neighbor MAC addresses at all (see the app's README) —
can pick up actual MAC addresses instead of Apple's 02:00:00:00:00:00
placeholder.

Run this on any always-on machine on the same LAN as your phone: a
Raspberry Pi, a NAS, a home server, a spare laptop — anything that stays on
and isn't itself sandboxed the way iOS apps are. No third-party
dependencies, standard library only. Works on Linux (reads /proc/net/arp
directly) and falls back to parsing `arp -a` output elsewhere (macOS/BSD).

This is read-only: it reports the ARP entries the OS already resolved on
its own as a side effect of normal network traffic. It does not send ARP
packets, spoof addresses, or scan anything itself.

Usage:
    python3 netscan-agent.py [--port 8756] [--token SECRET]

Then in NetScan: Settings -> LAN-агент -> enter this machine's address
(e.g. 192.168.1.50:8756) and the same token, if you set one.
"""
import argparse
import json
import platform
import re
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def read_arp_table_linux():
    table = {}
    try:
        with open("/proc/net/arp") as f:
            next(f, None)  # header line
            for line in f:
                fields = line.split()
                if len(fields) < 4:
                    continue
                ip, flags, mac = fields[0], fields[2], fields[3]
                try:
                    flags_value = int(flags, 16)
                except ValueError:
                    continue
                # ATF_COM (0x2) marks a resolved entry; skip incomplete ones
                # and the all-zero placeholder the kernel uses for those.
                if flags_value & 0x2 and mac != "00:00:00:00:00:00":
                    table[ip] = mac.lower()
    except FileNotFoundError:
        pass
    return table


def read_arp_table_generic():
    """Fallback for macOS/BSD: parse `arp -a` output, e.g. lines like
    'hostname (192.168.1.5) at a4:83:e7:11:22:33 on en0 ifscope [ethernet]'."""
    table = {}
    try:
        output = subprocess.run(
            ["arp", "-a"], capture_output=True, text=True, timeout=5
        ).stdout
    except Exception:
        return table

    pattern = re.compile(r"\(([\d.]+)\)\s+at\s+([0-9a-fA-F:]{17})")
    for line in output.splitlines():
        match = pattern.search(line)
        if match:
            table[match.group(1)] = match.group(2).lower()
    return table


def read_arp_table():
    if platform.system() == "Linux":
        table = read_arp_table_linux()
        if table:
            return table
    return read_arp_table_generic()


def make_handler(token):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/arp":
                self.send_response(404)
                self.end_headers()
                return
            if token:
                expected = f"Bearer {token}"
                if self.headers.get("Authorization", "") != expected:
                    self.send_response(401)
                    self.end_headers()
                    return

            body = json.dumps(read_arp_table()).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):
            pass  # keep stdout quiet; nothing sensitive worth logging anyway

    return Handler


def main():
    parser = argparse.ArgumentParser(description="NetScan LAN agent")
    parser.add_argument("--port", type=int, default=8756)
    parser.add_argument(
        "--token", default="", help="Optional shared-secret clients must send"
    )
    args = parser.parse_args()

    server = ThreadingHTTPServer(("0.0.0.0", args.port), make_handler(args.token))
    token_state = "set" if args.token else "not set — anyone on your LAN can query this"
    print(f"NetScan agent listening on :{args.port} (token {token_state})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
