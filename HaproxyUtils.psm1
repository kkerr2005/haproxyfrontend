function Get-HaproxyConfig {
    param(
        [string]$ConfigPath = '/etc/haproxy/haproxy.cfg'
    )
    if (Test-Path $ConfigPath) {
        return Get-Content $ConfigPath -Raw
    }
    return $null
}

function Set-HaproxyConfig {
    param(
        [string]$Frontend,
        [string]$Backend,
        [string[]]$BackendServers,
        [ValidateSet('http', 'tcp')]
        [string]$Mode = 'http',
        [int]$Port = 80,
        [string]$ConfigPath = '/etc/haproxy/haproxy.cfg'
    )
    
    $config = @"
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 4096
    
defaults
    log     global
    mode    $Mode
    option  ${Mode}log
    option  dontlognull
    retries 3
    timeout connect 5000
    timeout client  50000
    timeout server  50000

frontend $Frontend
    bind *:$Port
    mode $Mode
    default_backend $Backend

backend $Backend
    mode $Mode
"@

    foreach ($server in $BackendServers) {
        $config += "`n    server server-$($server.Replace('.', '-')) $server check"
    }

    $config | Out-File -FilePath $ConfigPath -Force -Encoding utf8
    return $true
}

function Test-HaproxyConfig {
    param(
        [string]$ConfigPath = '/etc/haproxy/haproxy.cfg'
    )
    
    $result = Start-Process "haproxy" -ArgumentList "-c -f $ConfigPath" -Wait -PassThru
    return $result.ExitCode -eq 0
}

Export-ModuleMember -Function Get-HaproxyConfig, Set-HaproxyConfig, Test-HaproxyConfig