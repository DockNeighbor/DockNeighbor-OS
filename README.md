# DockNeighbor OS

**The software inside the DockNeighbor Station.**

A DockNeighbor Station is the small box at a marina, a club, a private dock, or aboard your own boat
that hears every DockNeighbor sensor within about a mile and carries their readings to the cloud. The
bilge, the batteries, the shore power, the anchor: watched around the clock, with the alarm reaching you
first and the neighbors you choose only if it keeps going.

DockNeighbor OS is what that box runs. It is built on [OpenWrt](https://openwrt.org), tuned for one
job, and kept up to date on its own.

**Learn about DockNeighbor:** [www.dockneighbor.com](https://www.dockneighbor.com)

## What the station does for you

- **One box covers the whole dock.** A marina runs a station for every slip. Owners put sensors on
  their boats, scan them into the app, and they report from the day they arrive. Nothing of theirs to
  plug in, nothing to keep online. [How it works →](https://www.dockneighbor.com/how-it-works/)
- **Or take it with you.** No station where you keep the boat, or a boat that cruises? Carry the
  station aboard. The 4G model takes your own SIM and needs nothing from the dock.
  [DockNeighbor Nomad →](https://www.dockneighbor.com/nomad/)
- **It keeps watching when the internet doesn't.** Lose the connection and the station keeps
  listening; when the link returns, it sends what it heard.
- **Set up from the app in minutes.** Buy the station, plug it in, and the app does the rest. No
  console, no settings page, nothing to log in to.
- **It updates itself.** Fixes and improvements arrive signed, in the background, with no visit to the
  box.
- **Hosting one earns your plan.** Boats that choose your station as their home earn you credits,
  and credits earn you a free plan. [Host a station →](https://www.dockneighbor.com/network/)

## Which hardware

DockNeighbor OS runs on the SenseCAP M2 Multi-Platform LoRaWAN gateway, US915: the standard M2 for a
marina or a boat with internet, and the M2-4G for a boat or marina that needs its own cellular link.
Exact models and where to buy them are on
[Supported Devices](https://www.dockneighbor.com/devices/#station). Buy exactly those models; look-alike
gateways made for other networks will not work as a DockNeighbor Station.

## For marinas, yards and clubs

Marina Manager by DockNeighbor puts every boat in your slips on one board, every owner one message
away, and gives the people who tie up with you a reason to stay.
[Marina Manager by DockNeighbor →](https://www.dockneighbor.com/marina/)

## What is in this repository

This repository is the source for the open-source software in DockNeighbor Station images. The station
runs OpenWrt, which is mostly licensed under the GNU General Public License, version 2 (GPL-2.0). That
licence requires the source, including DockNeighbor's changes, to be available to everyone who receives the
software. It is published here:

- the board support for the SenseCAP M2, as a patch to OpenWrt (`station/openwrt/patches/`);
- the OpenWrt build configuration (`station/openwrt/bootstrap.diffconfig`) and the exact OpenWrt release it
  builds on (`station/openwrt/VERSION`);
- the OpenWrt files the station image replaces (`station/openwrt/files/`);
- a source archive for each station release, on this repository's Releases page.

[station/README.md](station/README.md) says how these fit together.

DockNeighbor's own software is not included. The station's own packages (the `dn-*` entries in the build
configuration), the apps and the cloud are private and proprietary.

The GL.iNet router images ("hub-lite") this repository built before the station are retired. Their build
files remain at the `hub-lite-os-v*` tags.

Questions about the product belong on the website's [support page](https://www.dockneighbor.com/support/).
Questions about this repository's licences and source are welcome as issues here.

## Licence

The scripts in this repository are Apache-2.0; see [NOTICE](NOTICE). The files under `station/openwrt/`
change OpenWrt and are under its licence, GPL-2.0, except where a file names its own (the M2's device tree
is GPL-2.0-or-later OR MIT). OpenWrt, the Linux kernel and the other open-source packages in a station image
carry their own licences, and their source is in each station release's source archive.
