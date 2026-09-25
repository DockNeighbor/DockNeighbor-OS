# DockNeighbor OS

Firmware for DockNeighbor devices, built on upstream [OpenWrt](https://openwrt.org). One OS, one
settings format and one device contract across every brand of hardware we support.

This repo holds **images**: how DockNeighbor software ships on a given piece of hardware. The software
itself (the hub-lite, the full hub daemon, the `/api/hub/*` device contract) lives in
[DockNeighbor-Hub](https://github.com/DockNeighbor/DockNeighbor-Hub). Images are assembled only from its
signed releases, pinned by version and hash, never copied in.

| Profile | Boards | Runs | Status |
|---|---|---|---|
| **hub-lite** | GL.iNet GL-MT300N-V2 (`ramips/mt76x8`), GL.iNet GL-X750 with LTE (`ath79/generic`) | the hub-lite (POSIX shell, on the router) | first profile |

A **profile** is a role (hub-lite: the router runs the hub-lite); a **board** is the hardware it runs on. Each board of
a profile is a directory, `profiles/<profile>/boards/<device>/`: its upstream pins (target, SDK, ImageBuilder and the
plain upstream image, by sha256), board name, firmware partition size, extra packages and files, and its release
channel.

## hub-lite

The on-boat hub for a boat with no hub computer aboard: the router runs the
[DockNeighbor hub-lite](https://github.com/DockNeighbor/DockNeighbor-Hub/tree/main/hub-lite) itself.
The image is upstream OpenWrt 24.10.8 for the board, plus:

- **The hub-lite** (`brvg-hub-lite`), taken from the Hub's signed feed. The build verifies the feed's
  signature and the package hash before using it.
- **dropbear with Ed25519.** Upstream builds `ramips/mt76x8` as `small_flash`, which compiles Ed25519
  out of dropbear, so an Ed25519 key is silently ignored there. (Every board gets the same dropbear build.)
- **`dn-handoff`**: carries the router's settings across the flash (below).
- **On the GL-X750, its LTE modem**, the upstream OpenWrt way: QMI (`uqmi`, netifd `proto qmi` on
  `/dev/cdc-wdm0`) with the modem's serial ports (`kmod-usb-serial-option`), USB GPS support (`kmod-usb-acm`), and
  the USB port's power switched on at boot (GPIO2, which upstream leaves off). The modem's APN, PIN and
  authentication come across the flash in the site file.
- **No local web page**: the DockNeighbor apps are the interface. There's no LuCI, and the system
  uhttpd is disabled. The hub-lite runs its own uhttpd instance for its port-8722 door.

### Flashing from the vendor firmware in one step

`handoff/` holds the flow the app runs over SSH on the vendor's stock firmware:

1. A **reader** for that vendor (`handoff/read-glinet.sh`) reads the router's LAN address, access point,
   uplink, LTE modem settings, DHCP reservations, admin password hash and SSH keys, and writes them as one brand-neutral
   site file (`/etc/dn/site.json`, format in [`handoff/README.md`](handoff/README.md)) inside a
   sysupgrade config tarball. Secrets never leave the router.
2. `sysupgrade -f /tmp/dn-handoff.tgz <image>` flashes the image and restores that tarball.
3. On first boot, `dn-handoff` in the image turns the site file into this firmware's own settings, so
   the router comes back on the same address, Wi-Fi and uplink, with the same admin password.

Proven on a GL-MT300N-V2 on 2026-09-24: stock GL.iNet 4.3.28 → upstream OpenWrt 24.10.8, back on its
uplink with no second step.

## The DN device API

GL.iNet's closed RPC is gone on DockNeighbor OS. In its place, `dn-net` reads and changes the router's network
settings as JSON, in the shapes of the app's network-device driver, and the hub-lite serves it on its port-8722
door as `/api/hub/net/*` (the route table is in DockNeighbor-Hub's `hub-lite/hub-lite-api.sh`). Reading needs
monitor access and changing needs configure access; a monitor sees the Wi-Fi settings without their keys.

| Area | Verbs |
|---|---|
| Internet | `wan`; the Wi-Fi uplink: `uplink-scan`, `uplink-get`, `uplink-join`, `uplink-disconnect`, `uplink-saved`, `uplink-forget` |
| LAN and Wi-Fi | `lan-get`, `lan-set`, `wifi-get`, `wifi-set` |
| Clients | `clients`, `client-block`, `reservations`, `reservation-add`, `reservation-remove` |
| Mode | `mode-get`, `mode-set`: `router` (firewall and NAT) or `bridge` (no firewall, NAT or DHCP server). `via: wired` (default): the WAN port joins the LAN. `via: wifi`: relayd bridges the LAN onto the Wi-Fi uplink, whose network hands out every address; the WAN port is off. Bridge mode reverts to router mode by itself if it gets no address within 180 s. |
| Device | `reboot`; `admin-password` (`{current, next}`): changes root's password only after `dn-auth` proves the current one. |

A Wi-Fi uplink's firewall follows its role: `lan` when the router joined the boat's own network (open like the
LAN), `wan` for an internet source such as marina Wi-Fi (restricted, the default).

## Upgrades: two levels

| Level | Replaces | From | Keeps |
|---|---|---|---|
| **1: hub-lite** | the `brvg-hub-lite` package | DockNeighbor-Hub's signed opkg feed (key `b0ff2bec314c57d3`), via the hub-lite's own `self_update` | everything |
| **1: dn-\* packages** | DockNeighbor OS's own packages (`dn-handoff`, `dn-os-upgrade`, `dn-hub-lite-os`, `dn-net`, `dn-auth`) | this repo's signed `dn_os` feed (key `1c44072d07e3e228`), via `dn-pkg-upgrade` | everything |
| **2: OS** | the whole firmware | `dn-os-upgrade`: this repo's signed release channel (key `3420e953f030f5a8`) | settings, the hub-lite's config and member keys |

The image is a known-good baseline for the kernel, drivers and base OS. Every package defined in `feed/` is also
published to the `dn_os` feed (rolling release `feed`, on each merge to `main` that touches `feed/`). One signed
index serves every board: an arch-independent package is listed once, and a compiled one once per board arch
(`mipsel_24kc`, `mips_24kc`), built by that board's SDK; opkg reads only the entries for its own arch. so a fix to
one reaches routers without a new firmware. `dn-pkg-upgrade` upgrades only packages that feed carries, and
restarts only the services they own. A PR that changes a package without bumping its version fails CI, because
opkg would never deliver it. opkg refuses any index that fails its signature.

`dn-os-upgrade check` reports `{current, available, upgrade, hubLite}`, and `dn-os-upgrade apply [--detach]` upgrades.
Each board has its own channel manifest (`channel-hub-lite/<device>.json`, the URL in its `/etc/dn-release`).
A router takes an OS release only when the manifest is signed by a key baked into its image, names its board
and profile, and is **strictly newer** than what it runs, so a replayed older manifest can't downgrade it. The
image must then match the manifest's sha256 and pass `sysupgrade -T`.

A new image carries its own hub-lite, which may be older than one level 1 installed. So before a level-2
upgrade the router records its hub-lite version (`/etc/dn/hub-lite.min`), and afterwards
`dn-hub-lite-restore` reinstalls from the feed until it is back at that version or newer.

**Releasing:** bump `DN_OS_VERSION` in `profiles/hub-lite/profile.env`, then push the tag
`hub-lite-os-v<version>`. The release workflow builds every board, signs one manifest per board (`<device>.json`),
publishes the release, and then moves the rolling `channel-hub-lite` release to it.

## Building

hub-lite needs x86-64 Linux with the OpenWrt ImageBuilder prerequisites (see the CI workflow):

```sh
sh scripts/build-hub-lite.sh glinet_gl-x750    # -> out/hub-lite/glinet_gl-x750/
sh scripts/build-hub-lite.sh                   # every board
```

Every upstream download is pinned by sha256, in `profiles/hub-lite/upstream.env` (shared) and each
`profiles/hub-lite/boards/<device>/board.env`. Those hashes come from
OpenWrt's `sha256sums` for the release, whose signature was verified against the 24.10 release key
(`d310c6f2833e97f7`) when they were pinned.

## Licence

Apache-2.0. See [NOTICE](NOTICE).
