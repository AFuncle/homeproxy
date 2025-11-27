# HomeProxy (Xray核心)

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
- XHTTP（主要是sing-box不支持这个）

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
<img width="1072" height="773" alt="image" src="https://github.com/user-attachments/assets/99cedf1c-123c-435a-8446-dd5358ec8487" />
<img width="965" height="1219" alt="image" src="https://github.com/user-attachments/assets/9b69fbe9-b854-4845-a2c6-9879e6f9f5c8" />
<img width="1029" height="1202" alt="image" src="https://github.com/user-attachments/assets/7868222d-f109-4b23-b546-54f8dfdff2b5" />

