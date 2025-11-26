# HomeProxy (Xray Edition)

基于 immortalwrt/homeproxy 修改，将代理核心从 sing-box 切换为 Xray-core。

## 支持的协议

- HTTP / HTTPS
- SOCKS4 / SOCKS5
- Shadowsocks
- Trojan
- VLESS (支持 REALITY)
- VMess

## 支持的传输层

- TCP
- gRPC
- HTTP/2
- HTTPUpgrade
- QUIC
- WebSocket
- XHTTP

## 路由模式

- GFWList
- 绕过中国大陆
- 仅代理中国大陆
- 全局代理
- 自定义路由

## 代理模式

- Redirect TCP
- Redirect TCP + TProxy UDP
- TProxy TCP/UDP

## 依赖

- xray-core
- v2ray-geoip
- v2ray-geosite

## 安装

从 [Releases](../../releases) 页面下载对应架构的 ipk 安装包，然后：

```bash
# 安装依赖
opkg update
opkg install xray-core v2ray-geoip v2ray-geosite

# 安装本插件
opkg install luci-app-homeproxy_*.ipk
opkg install luci-i18n-homeproxy-zh-cn_*.ipk  # 中文语言包（可选）
```
