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
  non-secret fields; the Wi-Fi keys, the SIM PIN, the APN password and the password hash stay inside the
  tarball, on the router. GL.iNet 4.x keeps the modem as a network interface named after its USB path
  (`modem_1_1_2` on the GL-X750), or in some releases per SIM in `/etc/config/glmodem`; the reader takes either,
  maps GL's `NONE`/`PAP`/`CHAP`/`PAP/CHAP` and `ip_type` to OpenWrt's values, and leaves out (with a warning)
  anything the renderer would refuse, so one odd field can't keep the whole site from applying.
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
  "ap": { "ssid": "…", "enc": "psk2", "key": "…", "band": "2g" },
  "uplink": { "type": "wifi", "ssid": "…", "enc": "psk-mixed", "key": "…", "role": "lan", "band": "5g" },
  "lte": { "apn": "…", "pincode": "…", "auth": "both", "username": "…", "password": "…", "pdptype": "ipv4v6" },
  "reservations": [ { "name": "…", "mac": "…", "ip": "…" } ],
  "rootHash": "$5$…"
}
```

| Field | Carried because |
|---|---|
| `lan` | The boat's devices and their webhooks point at the router's address (Shellys report to it). |
| `ap` | The boat's devices are joined to this Wi-Fi. |
| `uplink` | The router must get back online by itself. The access-point BSSID is **not** carried: pinning one breaks on a mesh or at a new berth. Its `role` sets the firewall: `lan` (the router joined the boat's own network, e.g. Starlink's Wi-Fi, to be the hub-lite) gets its own `uplink` zone that **accepts input like LAN** and still NATs the router's own AP clients; `wan` (a Wi-Fi internet uplink, e.g. a marina's) gets the `wan` zone, which drops input. **Missing means `wan`.** The vendor config can't tell them apart, so the app sets it (`UPLINK_ROLE` for `read-glinet.sh`). |
| `band` (in `ap`, `uplink`) | `2g`, `5g` or `6g`: which radio, on a dual-band board. **Missing means `2g`**, so a site from an older reader still puts the access point on 2.4 GHz, which the boat's Shellys need (the GL-X750's `radio0` is its 5 GHz radio). A board without that band uses its first radio. The GL reader carries the router's 2.4 GHz LAN access point when it has one. |
| `lte` | The cellular modem's settings, so an LTE router is back online by itself (GL-X750). Rendered as upstream OpenWrt's `proto qmi` (uqmi) on `/dev/cdc-wdm0`, interface `lte`, metric 30 (behind a wired or Wi-Fi uplink), in the **`wan` zone**, restricted like any internet uplink. `apn` (empty: the SIM's default), `pincode` (4 to 8 digits), `auth` (`none`/`pap`/`chap`/`both`) with `username`/`password`, `pdptype` (`ipv4`/`ipv6`/`ipv4v6`), `disabled` (the owner switched it off). The PIN, username and password are secrets: in the tarball only, never printed. An unknown `auth` or `pdptype`, or a malformed PIN, fails the apply; a board whose image has no modem support skips the `lte` object and applies the rest. |
| `reservations` | Fixed addresses the hub-lite reaches devices at. |
| `rootHash` | The owner's admin password keeps working. It's a crypt hash, never the password. |
| `country` | Legal Wi-Fi channels. |

Every field is optional except `v`. `band` and `lte` were added without a version bump: an older renderer ignores
them (the access point on its first radio, no modem), which is what it did before. An unknown `v` fails the apply and is retried on the next boot, so a
newer reader can't half-configure an older firmware.

The tarball also carries `/etc/dropbear/authorized_keys` and the dropbear Ed25519 host key, so key access
and the router's SSH identity survive, and, on a router already running the hub-lite, its
`/etc/brvg-hub-lite.conf` and `.keys`, so its enrollment survives too.
