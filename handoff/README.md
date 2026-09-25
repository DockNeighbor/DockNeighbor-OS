# Site handoff: vendor firmware → DockNeighbor OS in one flash

The app flashes a router that is still on its vendor's firmware, and the router must come back on the same
network without a second trip. OpenWrt's `sysupgrade -f <tarball> <image>` restores a config tarball of
our choosing into the new firmware. We put one brand-neutral site file in it, never the vendor's own config
files: vendors lay out their config differently (GL.iNet's closed MediaTek driver names its radio `mt7628`
and its uplink `apcli0`; OpenWrt's `mt76` says `radio0`), so copying them across would be wrong.

```
vendor firmware                           DockNeighbor OS, first boot
┌───────────────────────┐   sysupgrade -f  ┌──────────────────────────────────┐
│ read-<vendor>.sh      │ ───────────────▶ │ /etc/uci-defaults/05-dn-handoff  │
│  → /etc/dn/site.json  │   tarball        │  → /usr/libexec/dn-handoff/apply │
│  + SSH keys           │                  │  → uci: network, wireless, dhcp, │
└───────────────────────┘                  │         firewall, /etc/shadow    │
                                           └──────────────────────────────────┘
```

- **One reader per vendor** (`read-glinet.sh`), run on the router over SSH by the app. It prints only
  non-secret fields; the Wi-Fi keys and the password hash stay inside the tarball, on the router.
- **One renderer** (`feed/dn-handoff`), shipped in the image, so each firmware renders its own config
  from the same file.
- The renderer records its outcome (no secrets) in `/etc/dn/handoff.result` and the kernel log, and
  deletes the site file after applying it.

## `site.json`, version 1

```json
{
  "v": 1,
  "source": "glinet 4.3.28 glinet,gl-mt300n-v2",
  "lan": { "ip": "192.168.8.1", "mask": "255.255.255.0" },
  "country": "US",
  "ap": { "ssid": "…", "enc": "psk2", "key": "…" },
  "uplink": { "type": "wifi", "ssid": "…", "enc": "psk-mixed", "key": "…" },
  "reservations": [ { "name": "…", "mac": "…", "ip": "…" } ],
  "rootHash": "$5$…"
}
```

| Field | Carried because |
|---|---|
| `lan` | The boat's devices and their webhooks point at the router's address (Shellys report to it). |
| `ap` | The boat's devices are joined to this Wi-Fi. |
| `uplink` | The router must get back online by itself. The access-point BSSID is **not** carried: pinning one breaks on a mesh or at a new berth. |
| `reservations` | Fixed addresses the hub-lite reaches devices at. |
| `rootHash` | The owner's admin password keeps working. It's a crypt hash, never the password. |
| `country` | Legal Wi-Fi channels. |

Every field is optional except `v`. An unknown `v` fails the apply and is retried on the next boot, so a
newer reader can't half-configure an older firmware.

The tarball also carries `/etc/dropbear/authorized_keys` and the dropbear Ed25519 host key, so key access
and the router's SSH identity survive.
