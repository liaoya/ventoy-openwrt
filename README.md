# README

**Use <https://firmware-selector.openwrt.org> if you want a image with customize package.**

This repo use the official [OpenWrt](https://openwrt.org/) to build a image for [Ventoy](https://www.ventoy.net) and allow to do cusmization.
[Ventoy](https://www.ventoy.net) is an open source tool to create bootable USB drive for ISO/WIM/IMG/VHD(x)/EFI files.
You can use it to run [OpenWrt](https://openwrt.org/) on an USB drive easily.
According to <https://github.com/ventoy/OpenWrtPlugin>, only `kmod-dax` and `kmod-dm` package is required.
The official OpenWrt x86 image does not include these two packages, see this topics <https://forum.openwrt.org/t/ventoy-hope-to-add-dm-kmod-to-the-img-by-default/94907>.
You can use [Image Builder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder).
Another options is use [Image Builder docker image](https://hub.docker.com/r/openwrtorg/imagebuilder/tags?page=1&name=x86-64).
This repo provide a script help you to create a image.

Now you can use one of the following image

- `docker.io/openwrtorg/imagebuilder:x86-64-22.03.0`
- `docker.io/openwrtorg/imagebuilder:x86-64-21.02.3`
- `docker.io/openwrtorg/imagebuilder:x86-64-19.07.10`
- `docker.io/openwrtorg/imagebuilder:x86-64-18.06.7`, this version is not recommend

There're no image after `18.06.7` for `18.06` series.

The following are some examples

```bash
# If you want some other mirror
# export OPENWRT_MIRROR_PATH=https://mirrors.cloud.tencent.com/openwrt

PACKAGES="${PACKAGES:+$PACKAGES }-wpad-mini -wpad-basic -dnsmasq"
PACKAGES="${PACKAGES:+$PACKAGES }dnsmasq-full wpad \
atop bash bind-dig coreutils-base64 curl diffutils dropbearconvert fdisk file \
ip-full ipset \
lscpu \
luci luci-theme-bootstrap \
nano pciutils procps-ng-pkill tcpdump tmux \
uci wget"
export PACKAGES

version=21.02.3
bash build.sh -v $version
```

```bash
# Use the third party repository
bash build.sh -p "luci-app-vlmcsd" -t /work/openwrt/package/22.03/x86-64

env PACKAGES="luci-app-vlmcsd" bash build.sh -t /work/openwrt/package/22.03/x86-64
```

```bash
# Customize the image with configuration or additional program

bash build.sh -k $PWD/config
```
