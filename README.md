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

DockNeighbor OS is built on OpenWrt, and this repository is where the firmware is assembled and where
the source that OpenWrt's licences require is published: the board support for the DockNeighbor
Station, the OpenWrt build configuration, and a source archive for each station release. DockNeighbor's
own software, the apps, the cloud, and the station's services, is private and proprietary and is not
here.

The repository also still carries the `hub-lite` profile for the GL.iNet routers that DockNeighbor
supported before the station. That product is retired: no new images are offered for it, and the
profile is kept only until its last devices are moved over.

Questions about the product belong on the website's [support page](https://www.dockneighbor.com/support/).
Questions about this repository's licences and source are welcome as issues here.

## Licence

The build scripts and packages in this repository are Apache-2.0; see [NOTICE](NOTICE). The OpenWrt
base and the Linux kernel carry their own licences, and their source, including DockNeighbor's changes
to them, is published here for every station release.
