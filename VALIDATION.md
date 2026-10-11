# 验证记录

核对日期：2026-10-11。固定 Hysteria 2.13.0、acme.sh 3.1.6。

## 已执行

| 项目 | 结果及范围 |
|---|---|
| 部署脚本静态检查 | ShellCheck 0.11.0 通过，独立复核结果为空警告列表；Bash 文件采用 LF 行尾。 |
| 独立源码审核 | 核对已有服务保护、凭据保持、官方文件 SHA-256、严格 TLS、独立 ACME 目录和续期任务；未发现剩余已知阻塞。属于静态审核，不等于部署实测。 |
| Windows 检查脚本 | Windows PowerShell 5.1 的 15 项测试全部通过；验证 IPv6 TCP、SSH 标识、6 秒总时限、EOF/读取超时、关闭端口及非法地址拒绝。UTF-8 BOM 已核实。 |
| 原生 Hysteria 集成 | 官方 Windows 2.13.0 二进制哈希与版本通过；在 IPv6 回环 ::1 的临时高端口实际完成 SOCKS5 → Hysteria2 → IPv6 HTTP 流量，启用严格 TLS、IP SAN、密码及 Salamander。错误密码、不受信任 CA 均被拒绝。共 5 项通过。 |
| PPT | 14 页、3 个原生可编辑表格；通过 PPTX 结构、布局、字体策略和导入检查，并逐页查看最终 PPTX 的渲染图。未在桌面 PowerPoint 内原生执行。 |

测试只使用隔离的临时进程与测试证书。测试 CA 通过测试客户端的 tls.ca 指定，没有加入系统信任；没有修改路由、Wi-Fi 或防火墙，没有进行 VPS 登录认证。

## 未执行 / 仍需现场验收

- 当前 Windows 环境无可用 Linux systemd 运行环境，Linux preflight mock 未执行，未计入通过项目。
- 新部署脚本尚未在真实 Debian / Ubuntu VPS 完整运行。
- 新脚本的公网 Let's Encrypt 签发与自动续期、商家 NAT6、公网 UDP 回程尚未实测。
- 新脚本生成节点的 v2rayN / iPhone Shadowrocket 端到端访问仍需在目标网络验收。
- 没有连接、替换或改变当前已经可用的生产 VPS 服务。

今天人工部署的成功结果用于整理教程，不能替代新脚本自动化部署的验收。执行本机 --check、看到服务 active 或 TCP 连通，也不能替代客户端真实网页访问。

## 包内文件

- deploy-hy2-ipv6.sh：上传 VPS /root 后，以 root 运行。
- check-ipv6.ps1：在 Windows 上只读检查，不需要管理员权限或服务器密码。
- IPv6_Hysteria2_一键部署教程.pptx：可编辑教程。
- README.md：操作、前提、客户端字段和维护说明。
- VALIDATION.md：本记录。
- checksums.txt：上述五个文件的 SHA-256，支持 sha256sum -c checksums.txt。

脚本不配置家庭路由器；Cudy 的 IPv6 开关和穿透设置需在 Cudy APP 保存。脚本默认端口固定 UDP 443，已有 3X-UI 或其他服务占用时会退出。
