![GitHub License](https://img.shields.io/github/license/levi882/OpenWrt-nikki?style=for-the-badge&logo=github) ![GitHub Tag](https://img.shields.io/github/v/release/levi882/OpenWrt-nikki?style=for-the-badge&logo=github) ![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/levi882/OpenWrt-nikki/total?style=for-the-badge&logo=github) ![GitHub Repo stars](https://img.shields.io/github/stars/levi882/OpenWrt-nikki?style=for-the-badge&logo=github) [![Telegram](https://img.shields.io/badge/Telegram-gray?style=for-the-badge&logo=telegram)](https://t.me/nikkinikki_org)

English | [中文](README.zh.md)

# Nikki

Transparent Proxy with Mihomo on OpenWrt.

## Prerequisites

- OpenWrt >= 24.10
- Linux Kernel >= 5.13
- firewall4

## Feature

- Transparent Proxy (Redirect/TPROXY/TUN, IPv4 and/or IPv6)
- Access Control
- Profile Mixin
- Profile Editor
- Scheduled Restart
- Manual and scheduled China mainland IP list updates

## Install & Update

### A. Install From Feed (Recommended)

1. Add Feed

```shell
# only needs to be run once
wget -O - https://github.com/levi882/OpenWrt-nikki/raw/refs/heads/main/feed.sh | ash
```

2. Install

```shell
# you can install from shell or `Software` menu in LuCI
# for apk
apk add nikki@myfeed
apk add luci-app-nikki@myfeed
apk add luci-i18n-nikki-zh-cn@myfeed
```

### B. One-command Install or Update

```shell
wget -O - https://github.com/levi882/OpenWrt-nikki/raw/refs/heads/main/install.sh | ash
```

## Uninstall & Reset

```shell
wget -O - https://github.com/levi882/OpenWrt-nikki/raw/refs/heads/main/uninstall.sh | ash
```

### Package Compatibility

This fork's installer uses the signed [myfeed](https://openwrt-packages.pages.dev/openwrt-25.12/x86_64/myfeed/) repository. It currently publishes OpenWrt 25.12 / x86_64 APKs and the simplified Chinese translation. Other platforms can compile this fork from source.

Nikki keeps its established `/etc/init.d/nikki` entry point and `/etc/nikki` runtime paths. Release packages preserve the UCI configuration, mixin, subscriptions, profiles, and locally updated China mainland IP lists. The v1.26.2 release is validated with an APK round trip from official v1.26.1 to v1.26.2 and back to v1.26.1, including a protected local init script. If the incompatible wrapper from the earlier v1.26.2 package is protected, the upgrade backs it up to `/etc/nikki/nikki-r6-wrapper.bak` before restoring the full init entry point.

## Automatic Updates

[update-mihomo](https://github.com/levi882/OpenWrt-nikki/actions/workflows/dependabot.yml) checks the latest stable Mihomo release every Saturday at 04:17 Asia/Shanghai. It computes the OpenWrt source SHA256, builds and verifies the APKs, then updates this fork and publishes a new Release. Automatic releases use `v<LuCI version>-mihomo-<core version>` tags and retain previous releases. A current, complete release skips the build; incomplete releases are retried on the next check.

[Openwrt_packages](https://github.com/levi882/Openwrt_packages/actions/workflows/update-release-apks.yml) refreshes Release APKs and publishes the signed feed every Sunday at 04:17 Asia/Shanghai, about one day later. GitHub schedules can be delayed. To upgrade a router, use LuCI's package manager or run `apk update` followed by `apk add --upgrade mihomo-meta@myfeed nikki@myfeed luci-app-nikki@myfeed`.

## How To Use

See [Wiki](https://github.com/nikkinikki-org/OpenWrt-nikki/wiki)

## How does it work

1. Mixin and Update profile.
2. Run mihomo.
3. Set scheduled restart.
4. Set ip rule/route
5. Generate nftables and apply it.

Note that the steps above may change base on config.

## Compilation

```shell
# add feed
echo "src-git nikki https://github.com/levi882/OpenWrt-nikki.git;main" >> "feeds.conf.default"
# update & install feeds
./scripts/feeds update -a
./scripts/feeds install -a
# make package
make package/luci-app-nikki/compile
```

The package files will be found under `bin/packages/your_architecture/nikki`.

## Dependencies

- ca-bundle
- curl
- yq
- firewall4
- ip-full
- kmod-inet-diag
- kmod-nft-socket
- kmod-nft-tproxy
- kmod-tun
- kmod-dummy

## Contributors

[![Contributors](https://contrib.rocks/image?repo=nikkinikki-org/OpenWrt-nikki)](https://github.com/nikkinikki-org/OpenWrt-nikki/graphs/contributors)

## Special Thanks

- [@ApoisL](https://github.com/apoiston)
- [@xishang0128](https://github.com/xishang0128)
