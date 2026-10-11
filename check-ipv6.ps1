#Requires -Version 5.1
<#
只读 Windows IPv6 诊断，不切换 Wi-Fi、不修改路由器或服务、不进行 SSH 密码认证。
用法：powershell -NoProfile -File .\check-ipv6.ps1 -ServerIPv6 服务器公网IPv6
#>
param(
    [Parameter(Position = 0)]
    [string]$ServerIPv6,
    [ValidateRange(1, 65535)]
    [int]$SshPort = 22
)

function Test-Ipv6Ssh {
    param([System.Net.IPAddress]$Address, [int]$Port)

    $result = [ordered]@{ Connected = $false; Banner = ''; LocalAddress = ''; Detail = '' }
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $client = [System.Net.Sockets.TcpClient]::new([System.Net.Sockets.AddressFamily]::InterNetworkV6)
    try {
        $connect = $client.ConnectAsync($Address, $Port)
        if (-not $connect.Wait(6000)) {
            $result.Detail = '6 秒内未建立 TCP 连接。'
            return [pscustomobject]$result
        }
        $result.Connected = $true
        $result.LocalAddress = $client.Client.LocalEndPoint.Address.ToString()
        $remaining = 6000 - [int]$watch.ElapsedMilliseconds
        if ($remaining -gt 0) {
            $stream = $client.GetStream()
            $stream.ReadTimeout = $remaining
            $buffer = New-Object byte[] 256
            try {
                $count = $stream.Read($buffer, 0, $buffer.Length)
                $text = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $count)
                $banner = @($text -split "`r?`n" | Where-Object { $_ -match '^SSH-[12]\.[0-9]-' })
                if ($banner.Count -gt 0) { $result.Banner = $banner[0] -replace '[^\x20-\x7e]', '' }
            } catch {
                $result.Detail = 'TCP 已连接，但在剩余时限内未读到 SSH 标识；这不等于连接失败。'
            }
        }
        if (-not $result.Banner -and -not $result.Detail) {
            $result.Detail = 'TCP 已连接，未读到 SSH 标识。'
        }
        return [pscustomobject]$result
    } catch {
        $result.Detail = $_.Exception.GetBaseException().Message
        return [pscustomobject]$result
    } finally {
        $client.Dispose()
        $watch.Stop()
    }
}

if ([string]::IsNullOrWhiteSpace($ServerIPv6)) {
    $ServerIPv6 = Read-Host '请输入 VPS 的公网 IPv6（不是电脑或路由器的地址）'
}
$ServerIPv6 = $ServerIPv6.Trim()
if ($ServerIPv6.StartsWith('[') -and $ServerIPv6.EndsWith(']')) {
    $ServerIPv6 = $ServerIPv6.Substring(1, $ServerIPv6.Length - 2)
}
$address = $null
if (-not [System.Net.IPAddress]::TryParse($ServerIPv6, [ref]$address) -or
    $address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetworkV6 -or
    (($address.GetAddressBytes()[0] -band 0xe0) -ne 0x20) -or
    $address.ToString().StartsWith('2001:db8:', [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host '地址无效：请填写商家分配的公网 IPv6，不带端口或 /前缀长度。' -ForegroundColor Red
    exit 2
}

Write-Host "检查目标：[$address]:$SshPort；总连接与标识读取时限 6 秒。"
$wlan = & netsh.exe wlan show interfaces 2>$null
$ssids = @($wlan | ForEach-Object {
    if ($_ -match '^\s*SSID\s*:\s*(.+?)\s*$') { $Matches[1] }
})
Write-Host ('当前 Wi-Fi SSID：' + $(if ($ssids.Count) { $ssids -join ', ' } else { '未检测到已连接 Wi-Fi' }))

$addresses = @()
$routes = @()
$networkStateRead = $false
try {
    $upAdapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object Status -eq 'Up')
    $bindings = @(Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction Stop |
        Where-Object { $_.Name -in $upAdapters.Name })
    if ($bindings.Count -gt 0 -and -not @($bindings | Where-Object Enabled).Count) {
        Write-Host '已连接网卡的 IPv6 绑定未启用；请先核对 Windows 网卡的 IPv6 设置。' -ForegroundColor Yellow
    }
    $addresses = @(Get-NetIPAddress -AddressFamily IPv6 -AddressState Preferred -ErrorAction Stop |
        Where-Object {
            $ip = [System.Net.IPAddress]::Parse($_.IPAddress)
            -not $ip.IsIPv6LinkLocal -and -not $ip.IsIPv6Multicast -and
            -not [System.Net.IPAddress]::IsLoopback($ip) -and $_.IPAddress -ne '::'
        })
    if ($addresses.Count -gt 0) {
        Write-Host '当前非链路本地 IPv6 地址（fd 开头属于 ULA，不能单凭它证明公网可达）：'
        $addresses | Select-Object InterfaceAlias, InterfaceIndex, IPAddress, PrefixLength |
            Format-Table -AutoSize | Out-Host
    } else {
        Write-Host '当前未检测到可用的非链路本地 IPv6；fe80:: 仅能用于本地链路。' -ForegroundColor Yellow
    }
    $routes = @(Get-NetRoute -AddressFamily IPv6 -PolicyStore ActiveStore -ErrorAction Stop |
        Where-Object DestinationPrefix -eq '::/0')
    if ($routes.Count -gt 0) {
        Write-Host '当前 IPv6 默认路由：'
        $routes | Select-Object InterfaceAlias, InterfaceIndex, NextHop, RouteMetric, InterfaceMetric |
            Format-Table -AutoSize | Out-Host
    } else {
        Write-Host '当前没有 IPv6 默认路由。' -ForegroundColor Yellow
    }
    $networkStateRead = $true
} catch {
    Write-Host ('无法完整读取 Windows 网络状态：' + $_.Exception.GetBaseException().Message) -ForegroundColor Yellow
}
if ($networkStateRead -and (-not $addresses.Count -or -not $routes.Count)) {
    Write-Host '若上游 CPE 的 IPv6 正常，而此处连接 Cudy：核对 Cudy 已开启 IPv6、连接类型为穿透，并确认实际有线/WISP上联支持。请先看状态，勿盲改 AP 模式。' -ForegroundColor Yellow
}
Write-Host '如存在 VPN/TUN，需结合上面的接口判断实际路径；此脚本不会关闭它们。'
$probe = Test-Ipv6Ssh -Address $address -Port $SshPort
if ($probe.Connected) {
    Write-Host 'IPv6 TCP 连接成功。' -ForegroundColor Green
    Write-Host ('本次连接源地址：' + $probe.LocalAddress)
    if ($probe.Banner) { Write-Host ('SSH 标识：' + $probe.Banner) }
    if ($probe.Detail) { Write-Host $probe.Detail -ForegroundColor Yellow }
    Write-Host '此结果仅验证 TCP/标识；没有进行登录认证，也不代表 Hysteria2 的 UDP 443 已通过。'
    exit 0
}
Write-Host ('IPv6 TCP 连接未成功：' + $probe.Detail) -ForegroundColor Red
Write-Host '请核对客户端 IPv6 地址/路由、目标公网 IPv6和SSH端口，再检查上游线路与服务。'
exit 1
