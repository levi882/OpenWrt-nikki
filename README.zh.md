![GitHub License](https://img.shields.io/github/license/levi882/OpenWrt-nikki?style=for-the-badge&logo=github) ![GitHub Tag](https://img.shields.io/github/v/release/levi882/OpenWrt-nikki?style=for-the-badge&logo=github) ![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/levi882/OpenWrt-nikki/total?style=for-the-badge&logo=github) ![GitHub Repo stars](https://img.shields.io/github/stars/levi882/OpenWrt-nikki?style=for-the-badge&logo=github) [![Telegram](https://img.shields.io/badge/Telegram-gray?style=for-the-badge&logo=telegram)](https://t.me/nikkinikki_org)

中文 | [English](README.md)

# Nikki

在 OpenWrt 上使用 Mihomo 进行透明代理。

## 环境要求

- OpenWrt >= 24.10
- Linux Kernel >= 5.13
- firewall4

## 功能

- 透明代理 (Redirect/TPROXY/TUN, IPv4 和/或 IPv6)
- 访问控制
- 配置文件混入
- 配置文件编辑器
- 定时重启
- 中国大陆 IP 列表手动/定时更新

## 安装和更新

### A. 从软件源安装（推荐）

1. 添加源

```shell
# 只需运行一次
wget -O - https://github.com/levi882/OpenWrt-nikki/raw/refs/heads/main/feed.sh | ash
```

2. 安装

```shell
# 你可以从 shell 执行命令安装或者从 LuCI 的`软件包`菜单安装
# for apk
apk add nikki@myfeed
apk add luci-app-nikki@myfeed
apk add luci-i18n-nikki-zh-cn@myfeed
```

### B. 一键安装或更新

```shell
wget -O - https://github.com/levi882/OpenWrt-nikki/raw/refs/heads/main/install.sh | ash
```

## 卸载并重置

```shell
wget -O - https://github.com/levi882/OpenWrt-nikki/raw/refs/heads/main/uninstall.sh | ash
```

### 软件包兼容性

本 fork 的安装脚本使用 [myfeed](https://openwrt-packages.pages.dev/openwrt-25.12/x86_64/myfeed/)，当前发布 OpenWrt 25.12 / x86_64 APK 及简体中文语言包，安装时验证软件源签名。其他平台可从本 fork 源码编译。

Nikki 保持既有的 `/etc/init.d/nikki` 启动入口和 `/etc/nikki` 运行路径。发布包会保留 UCI 配置、混入文件、订阅、配置文件以及本地更新的中国大陆 IP 列表。v1.26.2 发布前会执行官方 v1.26.1 → v1.26.2 → v1.26.1 的 APK 往返测试，并覆盖启动脚本受保护的降级场景。如果系统保护了先前 v1.26.2 包的不兼容 wrapper，升级时会先备份到 `/etc/nikki/nikki-r6-wrapper.bak`，再恢复完整启动入口。

## 自动更新

[update-mihomo](https://github.com/levi882/OpenWrt-nikki/actions/workflows/dependabot.yml) 每周六北京时间 04:17 检查 Mihomo 最新稳定版。发现新版后，计算 OpenWrt 源码 SHA256、构建并校验 APK；全部成功才更新本 fork 的版本并发布新 Release。自动发布使用 `v<LuCI 版本>-mihomo-<核心版本>` 标签，保留以前的发布包；版本未变化且发布完整时跳过构建，未完成的发布会在下次检查重试。

[Openwrt_packages](https://github.com/levi882/Openwrt_packages/actions/workflows/update-release-apks.yml) 每周日北京时间 04:17 同步 Release 并重新签名发布软件源，比核心检查晚约一天。GitHub 定时任务可能延迟。路由器上可通过 LuCI 软件包页或 `apk update` 后执行 `apk add --upgrade mihomo-meta@myfeed nikki@myfeed luci-app-nikki@myfeed` 升级。

## 如何使用

查看 [Wiki](https://github.com/nikkinikki-org/OpenWrt-nikki/wiki)

## 如何工作

1. 混入并更新配置文件。
2. 启动 Mihomo。
3. 设置定时重启。
4. 配置 IP 规则/路由。
5. 生成防火墙配置并应用。

注意上述步骤可能因配置而变动。

## 编译

```shell
# 添加源
echo "src-git nikki https://github.com/levi882/OpenWrt-nikki.git;main" >> "feeds.conf.default"
# 更新并安装源
./scripts/feeds update -a
./scripts/feeds install -a
# 编译
make package/luci-app-nikki/compile
```

编译结果可以在`bin/packages/your_architecture/nikki`内找到。

## 依赖

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

## 贡献者

[![贡献者](https://contrib.rocks/image?repo=nikkinikki-org/OpenWrt-nikki)](https://github.com/nikkinikki-org/OpenWrt-nikki/graphs/contributors)

## 特别感谢

- [@ApoisL](https://github.com/apoiston)
- [@xishang0128](https://github.com/xishang0128)
