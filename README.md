# HomeProxy (Xray Edition)

基于 [immortalwrt/homeproxy](https://github.com/immortalwrt/homeproxy) 修改，将代理核心从 sing-box 切换为 Xray-core。

## 主要修改

### 代理核心
- 使用 Xray-core 替代 sing-box
- 配置生成脚本适配 Xray JSON 格式

### 支持的协议
- HTTP / HTTPS
- SOCKS4 / SOCKS5
- Shadowsocks
- Trojan
- VLESS (支持 REALITY)
- VMess

### 支持的传输层
- TCP
- gRPC
- HTTP/2
- HTTPUpgrade
- QUIC
- WebSocket
- XHTTP

### 路由规则
- 使用 geoip.dat / geosite.dat 规则文件
- 通过 opkg 管理 v2ray-geoip 和 v2ray-geosite 包
- 支持在线更新规则数据库

### 代理模式
- Redirect TCP
- Redirect TCP + TProxy UDP
- TProxy TCP/UDP

### 路由模式
- GFWList
- 绕过中国大陆
- 仅代理中国大陆
- 全局代理
- 自定义路由

## 依赖

- xray-core
- v2ray-geoip
- v2ray-geosite

## 安装

```bash
opkg update
opkg install xray-core v2ray-geoip v2ray-geosite
opkg install luci-app-homeproxy
```

## 致谢

- [immortalwrt/homeproxy](https://github.com/immortalwrt/homeproxy) - 原始项目
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core) - 代理核心
