# Knock

Replace `SERVER_IP`, `40000` and `YOUR_MESSAGE` with your IPv4 server, UDP port and exact configured message. Connect RDP from the same client immediately afterward. No reply is expected.

**Linux (nc):**

```bash
printf '%s' 'YOUR_MESSAGE' | nc -u -w 1 SERVER_IP 40000
```

**Windows PowerShell:**

```powershell
$udp = New-Object Net.Sockets.UdpClient
try {
    $bytes = [Text.Encoding]::UTF8.GetBytes('YOUR_MESSAGE')
    $null = $udp.Send($bytes, $bytes.Length, 'SERVER_IP', 40000)
}
finally { $udp.Dispose() }
mstsc.exe /v:SERVER_IP
```
