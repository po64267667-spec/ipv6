# 原生 Hysteria2 IPv6 一键部署

适用于运行 systemd 的 **Debian 12/13、Ubuntu 22.04/24.04**，支持 amd64 / arm64；不需要域名、3X-UI 或 Docker。默认安装只询问一个值：**商家分配的公网 IPv6**。认证密码和 Salamander 混淆密码随机生成，完成后直接显示原始链接和二维码。

[中文 PPT 教程](IPv6_Hysteria2_一键部署教程.pptx) · [Windows 只读 IPv6 检查工具](check-ipv6.ps1) · [验证记录](VALIDATION.md)

截至 2026-10-11，固定使用官方稳定版本 **Hysteria 2.13.0**（2026-10-05 发布）和 **acme.sh 3.1.6**。程序及 ACME 脚本均来自官方固定版本，先验证 SHA-256，再执行。

## 最简单入口：一条命令

用 **FinalShell 或其他 SSH 客户端登录 VPS 的 root 终端**，复制下面整行执行：

```bash
curl -fL --proto '=https' --proto-redir '=https' https://raw.githubusercontent.com/po64267667-spec/ipv6/main/deploy-hy2-ipv6.sh -o /root/deploy-hy2-ipv6.sh && printf '%s  %s\n' '4d610bb81e86584ca1f27421171bb66ee58dcdd944f9b22d98581aa6478f2d51' '/root/deploy-hy2-ipv6.sh' | sha256sum -c - && bash /root/deploy-hy2-ipv6.sh
```

命令通过 HTTPS 将脚本下载至 `/root/deploy-hy2-ipv6.sh`，核对本部署脚本的 SHA-256，匹配后才运行。下载或校验失败就停止；保留 HTTPS 证书验证，不使用 `-k` 或 `curl | bash`。

随后只需输入商家给出的**真实公网 IPv6**，等待自动完成，复制原始 `hysteria2://` 链接或扫码导入客户端。无需提供邮箱。

如果缺少 `curl` 或系统 CA 证书，先执行：

```bash
apt-get update && apt-get install -y curl ca-certificates
```

上面的一条入口适用于本 README 对应的脚本版本；仓库更新脚本时需同步更新这里的 SHA-256。校验失败时先核对版本，不要跳过校验。

## 手动上传备用方法

下载仓库中的 `deploy-hy2-ipv6.sh`，用 FinalShell/SFTP 上传至准备部署的 VPS 的 `/root/` 目录，以 root 执行：

```bash
printf '%s  %s\n' '4d610bb81e86584ca1f27421171bb66ee58dcdd944f9b22d98581aa6478f2d51' '/root/deploy-hy2-ipv6.sh' | sha256sum -c - && bash /root/deploy-hy2-ipv6.sh
```

已校验的脚本也可直接指定地址：

```bash
bash /root/deploy-hy2-ipv6.sh --ipv6 2001:db8::10
```

**`2001:db8::10` 仅是文档示例，必须替换为真实公网 IPv6。** guest 网卡可能只有 `fd42:…` 等 ULA 地址，商家通过 NAT6 将公网 IPv6 映射给 guest。这种情况下仍填商家分配的公网地址；脚本监听 `[::]:443`，不把公网地址强行绑定到 guest 网卡。

## 开始前必须具备

- 客户端网络有可用 IPv6；Windows 的 v2rayN、iPhone 的 Shadowrocket 需支持 Hysteria2。
- 商家允许公网 IPv6 **TCP 80** 和 **UDP 443** 到达 VPS。UDP 443 用于 Hysteria2；TCP 80 用于初次申请和之后自动续期。
- 本机 TCP 80 空闲，UDP 443 空闲。已有本包服务可安全重复运行；其他服务占用则退出。
- VPS 可以安装系统软件包并通过 HTTPS 访问官方 GitHub 与 Let’s Encrypt。

若现有 3X-UI 正在使用 UDP 443，脚本会安全退出。请部署到新主机，或先单独规划已有服务；脚本不会停止 3X-UI、修改 SSH、清空防火墙或修改 Windows/路由器。若 UFW 正在运行，只添加 TCP 80 / UDP 443 放行规则；其他主机/商家防火墙保持原有配置。

## Windows 先检查 IPv6

下载 [check-ipv6.ps1](check-ipv6.ps1)，在文件所在目录打开 PowerShell，运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\check-ipv6.ps1
```

输入 **VPS 的真实公网 IPv6**。也可以直接指定地址和 SSH 端口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\check-ipv6.ps1 -ServerIPv6 2001:db8::10 -SshPort 22
```

示例地址仍需替换。工具显示当前 Wi-Fi、IPv6 地址及默认路由，再尝试到 VPS 的 IPv6 TCP/SSH 标识读取；不会进行密码登录或更改网络设置。仅有 `fe80::` 链路本地地址，或者只有 `fd…` ULA 地址，不能证明电脑已经具备公网 IPv6 通路。TCP/SSH 成功也不能证明 Hysteria2 的 UDP 443 可用，最后仍要通过客户端访问网页验证。

## Cudy：IPv6 → 穿透

如果上游 CPE 已确认具有正常的 IPv6 通路，而连接 Cudy 后电脑没有可用 IPv6，可在 **Cudy 管理页 → IPv6** 开启 IPv6，将 **连接类型**设置为 **穿透 / Passthrough** 并保存。穿透让下游设备从上游获得 IPv6 设置；具体选项和有线/WISP 上联支持取决于型号与固件。[Cudy 官方 IPv6 说明](https://docs.cudy.com/user_guide/wireless_router/network/)

保存后等待电脑重新获取地址，必要时重新连接当前 Wi-Fi，再运行 `check-ipv6.ps1`，确认地址、`::/0` 默认路由和 IPv6 TCP 连接的结果。结合检查显示的接口判断实际流量是否经过 VPN/TUN。

这一步配置的是**本地 Cudy 路由器**；`deploy-hy2-ipv6.sh` 配置的是**远程 VPS**；`check-ipv6.ps1` 负责**只读诊断 Windows 到 VPS 的通路**。三者分别操作，不会由 VPS 安装脚本自动完成路由器设置。

## 安装完成后的维护操作

脚本保存在 `/root/deploy-hy2-ipv6.sh`。安装完成或重新登录 VPS 后，都可以直接使用下面的绝对路径命令；已保存的凭据、配置和服务位于 `/etc/hy2-ipv6-kit/` 等固定路径。

| 操作 | 命令 | 结果 |
|---|---|---|
| 安装 / 失败后继续 | `bash /root/deploy-hy2-ipv6.sh` | 保留已有密码、IPv6、配置；继续缺失步骤 |
| 只读检查 | `bash /root/deploy-hy2-ipv6.sh --check` | 端口、服务、证书日期；不输出密码或二维码 |
| 显示连接信息 | `bash /root/deploy-hy2-ipv6.sh show` | 原始链接、终端二维码及 PNG 路径 |

安装成功也会直接显示链接与终端二维码。链接和二维码包含连接密码，分享它们就等于分享该节点的访问权。

## 客户端填写

优先导入脚本生成的原始链接。导入后检查：

| 字段 | 值 |
|---|---|
| 协议 | Hysteria2 |
| 服务器 | 输入的真实公网 IPv6 |
| 端口 | 443 |
| 密码 | 自动生成的认证密码 |
| 混淆 | Salamander |
| 混淆密码 | 自动生成的混淆密码 |
| TLS 证书校验 | 开启；链接没有 `insecure=1` |
| SNI / 证书校验名称 | 输入的真实公网 IPv6，与服务器地址相同；不要填无关网站域名 |

IPv6 在 URI 中使用 `[IPv6]:443`，链接也显式携带 URL 编码的 `sni=公网IPv6`，供 GUI 客户端保留正确的证书校验对象。原生 Hysteria2 客户端可以从服务器地址自动提取，但本包链接仍明确提供该字段。客户端如果要求单独填写服务器地址，按客户端字段要求填写 IPv6。v2rayN 的具体内核、旧版客户端的导入行为可能不同：若连接失败，查看错误日志并核对 IPv6 证书校验对象，不用关闭证书校验解决。

## 保存位置与证书续期

| 路径 / 服务 | 用途 |
|---|---|
| `/etc/hy2-ipv6-kit/server.yaml` | 原生服务器配置，权限 0600 |
| `/etc/hy2-ipv6-kit/credentials.env` | 公网 IPv6 和两种密码，权限 0600 |
| `/etc/hy2-ipv6-kit/connection.txt` | 原始连接链接，权限 0600 |
| `/etc/hy2-ipv6-kit/connection.png` | 二维码，权限 0600 |
| `/etc/hy2-ipv6-kit/tls/fullchain.pem` | 正式证书完整链 |
| `/etc/hy2-ipv6-kit/tls/private.key` | 证书私钥，权限 0600 |
| `/etc/hy2-ipv6-kit/acme/` | 独立 ACME 程序、账户、证书状态和续期日志 |
| `/usr/local/lib/hy2-ipv6-kit/hysteria` | 校验过的原生程序 |
| `hy2-ipv6-kit.service` | systemd 原生服务 |
| `/etc/cron.d/hy2-ipv6-kit` | 每 6 小时检查自动续期 |

证书来自 **Let’s Encrypt 免费正式 CA**，使用 `shortlived` profile，有效期 **160 小时**。设置 `--days 3`，约第 3 天开始续期。自动续期必须继续满足 IPv6 TCP 80 可达、本机 TCP 80 空闲和 cron 正常运行。

续期会更新固定证书文件，并执行 `systemctl restart hy2-ipv6-kit.service`，让原生服务器立即读取新证书。重启期间现有连接可能短暂断开。脚本的 ACME 状态与已有 `/root/.acme.sh` 分离，不改已有证书项目。

## 常见问题

- **提示 UDP 443 被占用**：先运行 `ss -lunp 'sport = :443'` 找到所属进程。不要盲目停止现有生产服务；本脚本默认端口固定 443。
- **Let’s Encrypt 超时或签发失败**：核对填写的是公网 IPv6，商家 NAT6 映射存在，IPv6 TCP 80 放行且没有其他 HTTP 服务占用。证书失败会停止部署并保留已生成的凭据，修好后直接重跑。
- **服务 active 但客户端超时**：核对客户端本身有 IPv6，商家及主机防火墙开放 IPv6 UDP 443，混淆类型/密码与服务端一致。TCP 80 成功不能证明 UDP 443 可达。
- **证书过期**：检查 `systemctl is-active cron`、`/etc/cron.d/hy2-ipv6-kit` 和 `/etc/hy2-ipv6-kit/acme/renew.log`。恢复 TCP 80 可达后重跑安装。
- **512 MB 主机**：脚本使用原生预编译程序，不编译 Go，不安装 Web 面板或 Docker；不修改内核 BBR/sysctl 参数。实际内存和速度依赖连接数量、网络及出站环境。

手动查看服务日志（日志是否含敏感内容应自行检查后再分享）：

```bash
journalctl -u hy2-ipv6-kit.service -n 50 --no-pager
```

## 版本和来源

- [Hysteria 官方稳定版 2.13.0](https://github.com/HyNetworks/hysteria/releases/tag/app/v2.13.0)
- [Hysteria 官方服务器配置](https://v2.hysteria.network/docs/advanced/Full-Server-Config/)
- [Hysteria 官方 URI 规范](https://v2.hysteria.network/docs/developers/URI-Scheme/)
- [acme.sh 官方固定版 3.1.6](https://github.com/acmesh-official/acme.sh/releases/tag/3.1.6)
- [Let’s Encrypt IP 证书正式开放公告](https://letsencrypt.org/2026/01/15/6day-and-ip-general-availability)
- [Let’s Encrypt profile 定义](https://letsencrypt.org/docs/profiles/)

固定文件 SHA-256：

```text
deploy-hy2-ipv6.sh    4d610bb81e86584ca1f27421171bb66ee58dcdd944f9b22d98581aa6478f2d51
hysteria-linux-amd64  907ba8c9693edb104b20582681fb7dc15639d5b64a9cbb616a7b539190a86691
hysteria-linux-arm64  a68a61a84452ca250ce0368202521965ca9cc9d801a404f1dc9008ac6cf677a7
acme.sh 3.1.6        c7d68b021cfd6380ea83a82962abde5b484779fee0b97d38681dfa1396bbc8d7
```

## 验证边界

已完成的本地验证：

- ShellCheck 0.11.0 检查部署脚本通过，无警告；脚本为 LF 行尾。
- 官方 Windows 原生 Hysteria 2.13.0 二进制 SHA-256 与版本核验通过。
- 在本机 IPv6 回环 `::1` 的临时高端口，实际验证服务器 YAML、P-256 IP SAN 证书、严格 TLS 验证、密码认证、Salamander，以及 SOCKS5 → Hysteria2 → IPv6 HTTP 的真实流量。
- 错误认证密码和不受信任的 CA 均被拒绝。测试 CA 只由测试客户端 `tls.ca` 使用，没有安装到系统信任；没有修改 Windows 路由或防火墙。
- Windows 只读检查工具已完成 15 项实测检查。

具体检查项、证据和未验范围见 [VALIDATION.md](VALIDATION.md)。原生集成测试使用 Windows 回环环境，**不能视为 Linux systemd 部署成功**。

没有连接或部署当前生产 VPS，没有实测公网 Let’s Encrypt 签发/续期、商家 NAT6/UDP 回程、Windows v2rayN 或 iPhone Shadowrocket 端到端连接。脚本运行后的本机检查不代替客户端网页实测，也不保证绕过网络封锁。
