function Get-HaproxyConfig {
    param(
        [string]$ConfigPath = '/etc/haproxy/haproxy.cfg'
    )
    try {
        # Use sudo to read the config file
        $config = & sudo cat $ConfigPath 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $config
        }
        return $null
    }
    catch {
        Write-Error "Failed to read HAProxy configuration: $_"
        return $null
    }
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

    # Ensure Linux line endings
    $config = $config.Replace("`r`n", "`n")
    
    # Write to a temporary file first
    $tempFile = "/tmp/haproxy.cfg.tmp"
    [System.IO.File]::WriteAllText($tempFile, $config)
    
    # Use sudo to move the file to its final location with proper permissions
    try {
        & sudo mv $tempFile $ConfigPath
        & sudo chown haproxy:haproxy $ConfigPath
        & sudo chmod 644 $ConfigPath
        return $true
    }
    catch {
        Write-Error "Failed to set HAProxy configuration: $_"
        return $false
    }
}

function Test-HaproxyConfig {
    param(
        [string]$ConfigPath = '/etc/haproxy/haproxy.cfg'
    )
    
    try {
        $result = & haproxy -c -f $ConfigPath 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

Export-ModuleMember -Function Get-HaproxyConfig, Set-HaproxyConfig, Test-HaproxyConfig