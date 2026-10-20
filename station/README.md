# Station image: OpenWrt source

The DockNeighbor Station image (the SenseCAP M2, US915) is OpenWrt built from source. This directory holds
what DockNeighbor adds to OpenWrt to build it. Everything else comes from the public projects named below,
at the versions named here.

| Path | What it is |
|---|---|
| `openwrt/VERSION` | The OpenWrt repository, release tag and commit the image is built from. |
| `openwrt/patches/` | Patches to that OpenWrt tree, applied in order with `git am`. `0001` adds the SenseCAP M2 (WM7628N) board: its device tree, image definition, LEDs and network ports. |
| `openwrt/bootstrap.diffconfig` | The build configuration (`.config` before `make defconfig`). |
| `openwrt/files/` | Files the image puts in place of OpenWrt's own (OpenWrt's `files/` overlay). `etc/rc.button/reset` replaces base-files' reset-button handler. |
| `build-inputs.env` | The ChirpStack OpenWrt feed commit the radio's packages are built from, and the station build commit this directory was copied from. |

The `dn-*` lines in the build configuration select DockNeighbor's own packages. They are private and
proprietary, and are not part of this source.

## Rebuilding the OpenWrt parts

On x86-64 Linux with [OpenWrt's build prerequisites](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem):

```sh
. station/openwrt/VERSION; . station/build-inputs.env
git clone -b "$OPENWRT_TAG" "$OPENWRT_REPO" openwrt && cd openwrt
git checkout "$OPENWRT_COMMIT"
for p in ../station/openwrt/patches/*.patch; do git am "$p"; done
cp -R ../station/openwrt/files files
{ cat feeds.conf.default; echo "src-git chirpstack $CHIRPSTACK_FEED"; } > feeds.conf
./scripts/feeds update -a && ./scripts/feeds install -a
cp ../station/openwrt/bootstrap.diffconfig .config && make defconfig
make download && make
```

`scripts/check-station-inputs.sh` runs the first half of this on every change: the pinned commit, the
patches applying, and the configuration selecting the M2 and its radio.

Each station release's source archive is on this repository's Releases page.
