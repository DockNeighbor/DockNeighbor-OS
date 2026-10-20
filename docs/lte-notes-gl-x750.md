# LTE on OpenWrt: notes from the GL-X750

The retired hub-lite image ran on the GL.iNet GL-X750, which has a Quectel EC25-family LTE modem on USB
(in its mPCIe slot). This is what that image did to bring the modem up on plain OpenWrt 24.10, kept as the
starting point for modem support on the station. The code itself is at the last commit that carried it,
[`9d66bd9`](https://github.com/DockNeighbor/DockNeighbor-OS/tree/9d66bd9), and at the `hub-lite-os-v*` tags.

## Packages

`uqmi kmod-usb-net-qmi-wwan kmod-usb-serial-option`, plus `kmod-usb-acm` for a USB GPS on the X750's USB port
([board.env](https://github.com/DockNeighbor/DockNeighbor-OS/blob/9d66bd9/profiles/hub-lite/boards/glinet_gl-x750/board.env)).

- **QMI, the upstream way:** `uqmi` and netifd's `proto qmi` (`/lib/netifd/proto/qmi.sh`) on `/dev/cdc-wdm0`.
  ModemManager would not fit in flash.
- `kmod-usb-net-qmi-wwan` gives `/dev/cdc-wdm0` and `wwan0`.
- `kmod-usb-serial-option` gives the modem's AT and NMEA serial ports.

## USB power (GL-X750 only)

The X750's USB port power is switched by GPIO 2, active low, and upstream OpenWrt leaves it off. On 24.10's
kernel 6.6 the ath79 GPIO chip's base is 512, so the pin is 514. Upstream's `gpio_switch` service drives it at
every boot
([06-dn-usb-power](https://github.com/DockNeighbor/DockNeighbor-OS/blob/9d66bd9/profiles/hub-lite/boards/glinet_gl-x750/files/etc/uci-defaults/06-dn-usb-power)):

```sh
uci set system.dn_usb_power=gpio_switch
uci set system.dn_usb_power.name='USB power'
uci set system.dn_usb_power.gpio_pin=514
uci set system.dn_usb_power.value=0
uci commit system
```

Other boards power their modems differently. Only the netifd conventions below carry over.

## The interface

([dn-handoff `apply`](https://github.com/DockNeighbor/DockNeighbor-OS/blob/9d66bd9/feed/dn-handoff/files/usr/libexec/dn-handoff/apply#L116-L156))

| uci `network.lte` | Value |
|---|---|
| `proto` | `qmi` |
| `device` | `/dev/cdc-wdm0` |
| `apn` | unset for the SIM's default |
| `pincode` | 4 to 8 digits, when the SIM is locked |
| `auth` | `none`, `pap`, `chap` or `both`, with `username` and `password` |
| `pdptype` | `ip` (qmi.sh's name for IPv4), `ipv6` or `ipv4v6` |
| `metric` | `30`: behind a wired uplink (0) and a Wi-Fi uplink (20) |
| firewall | the `wan` zone; qmi.sh's `lte_4`/`lte_6` children inherit it |

- The PIN, username and password go into uci only. They are never printed or reported.
- An image without `/lib/netifd/proto/qmi.sh` skips the `lte` settings instead of failing.
- GL.iNet's stock 4.x firmware keeps the modem as an interface named after its USB path (`modem_1_1_2` on the
  X750), or in `/etc/config/glmodem` with one section per SIM
  ([read-glinet.sh](https://github.com/DockNeighbor/DockNeighbor-OS/blob/9d66bd9/handoff/read-glinet.sh#L35-L75)).

## Status

([dn-status `status`](https://github.com/DockNeighbor/DockNeighbor-OS/blob/9d66bd9/feed/dn-status/files/usr/libexec/dn-status/status#L38-L56))

- **Modem present:** `uci get network.lte.proto` is `qmi`.
- **Modem up:** `ifstatus lte` reports `"up": true`.
- **Internet via cellular:** the IPv4 default route's device is `ifstatus lte`'s `l3_device` (`wwan0`).
