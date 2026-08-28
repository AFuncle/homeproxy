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

## 流量分析

“流量分析”页面提供：

- 实时上传、下载速率折线图（最近 60 个采样点）
- Xray 启动后的累计上传、下载流量
- 直连、代理节点等最终出站流量排行
- 腾讯、百度、阿里、抖音、Bilibili、Google、YouTube、OpenAI 等域名组的精确字节统计和图表排行

基础统计始终可用。若要统计原本由防火墙快速直连的流量，并按服务商域名组归类，请在“客户端设置 → 路由设置”中开启“深度流量分析”。开启后，配置路由端口内的流量会经过 Xray 完成统计，再按照原有规则选择直连或代理；低性能路由器可能会有额外 CPU 占用。

服务商归类表位于 `/etc/homeproxy/resources/traffic_categories.json`。只能识别 Xray 能嗅探到域名的连接；纯 IP、无法嗅探或未包含在归类表中的流量仍计入总流量，但显示为未归类。

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
