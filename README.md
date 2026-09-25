# DockNeighbor OS

Firmware for DockNeighbor devices, built on upstream [OpenWrt](https://openwrt.org). One OS, one
settings format and one device contract across every brand of hardware we support.

This repo holds **images**: how DockNeighbor software ships on a given piece of hardware. The software
itself (the hub-lite, the full hub daemon, the `/api/hub/*` device contract) lives in
[DockNeighbor-Hub](https://github.com/DockNeighbor/DockNeighbor-Hub). Images are assembled only from its
signed releases, pinned by version and hash, never copied in.

| Profile | Hardware | Runs | Status |
|---|---|---|---|
| **hub-lite** | GL.iNet GL-MT300N-V2 | the hub-lite (POSIX shell, on the router) | first profile |

## hub-lite

The on-boat hub for a boat with no hub computer aboard: the router runs the
[DockNeighbor hub-lite](https://github.com/DockNeighbor/DockNeighbor-Hub/tree/main/hub-lite) itself.
The image is upstream OpenWrt 24.10.8 for the board, plus:

- **The hub-lite** (`brvg-hub-lite`), taken from the Hub's signed feed. The build verifies the feed's
  signature and the package hash before using it.
- **dropbear with Ed25519.** Upstream builds this target as `small_flash`, which compiles Ed25519
  out of dropbear, so an Ed25519 key is silently ignored there.
- **`dn-handoff`**: carries the router's settings across the flash (below).
- **No local web page**: the DockNeighbor apps are the interface. There's no LuCI, and the system
  uhttpd is disabled. The hub-lite runs its own uhttpd instance for its port-8722 door.

### Flashing from the vendor firmware in one step

`handoff/` holds the flow the app runs over SSH on the vendor's stock firmware:

1. A **reader** for that vendor (`handoff/read-glinet.sh`) reads the router's LAN address, access point,
   uplink, DHCP reservations, admin password hash and SSH keys, and writes them as one brand-neutral
   site file (`/etc/dn/site.json`, format in [`handoff/README.md`](handoff/README.md)) inside a
   sysupgrade config tarball. Secrets never leave the router.
2. `sysupgrade -f /tmp/dn-handoff.tgz <image>` flashes the image and restores that tarball.
3. On first boot, `dn-handoff` in the image turns the site file into this firmware's own settings, so
   the router comes back on the same address, Wi-Fi and uplink, with the same admin password.

Proven on a GL-MT300N-V2 on 2026-09-24: stock GL.iNet 4.3.28 → upstream OpenWrt 24.10.8, back on its
uplink with no second step.

## Building

hub-lite needs x86-64 Linux with the OpenWrt ImageBuilder prerequisites (see the CI workflow):

```sh
sh scripts/build-hub-lite.sh      # -> out/hub-lite/
```

Every upstream download is pinned by sha256 in `profiles/hub-lite/upstream.env`. Those hashes come from
OpenWrt's `sha256sums` for the release, whose signature was verified against the 24.10 release key
(`d310c6f2833e97f7`) when they were pinned.

## Licence

Apache-2.0. See [NOTICE](NOTICE).
