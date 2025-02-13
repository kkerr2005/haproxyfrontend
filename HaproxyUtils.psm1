function Get-HaproxyConfig {
    param(
        [string]$ConfigPath = '/etc/haproxy/haproxy.cfg',
        [switch]$Simple
    )
    try {
        Write-Host "Attempting to read HAProxy config from: $ConfigPath"
        # Use sudo to read the config file
        $configLines = & sudo cat $ConfigPath 2>&1
        Write-Host "Read command exit code: $LASTEXITCODE"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully read config file"
            
            if ($Simple) {
                $summary = "`n═══════════════════════════════════════`n"
                $summary += "      HAProxy Active Configuration      `n"
                $summary += "═══════════════════════════════════════`n`n"
                $currentSection = $null
                $frontendFound = $false
                $backendFound = $false
                
                foreach ($line in $configLines) {
                    $line = $line.Trim()
                    if ($line -match '^frontend\s+(\S+)') {
                        $frontendFound = $true
                        $currentSection = "frontend"
                        $summary += "► FRONTEND: $($matches[1])`n"
                    }
                    elseif ($line -match '^backend\s+(\S+)') {
                        $backendFound = $true
                        $currentSection = "backend"
                        $summary += "`n► BACKEND: $($matches[1])`n"
                    }
                    elseif ($line -match '^\s*bind\s+\*:(\d+)' -and $currentSection -eq "frontend") {
                        $summary += "   Port: $($matches[1])`n"
                    }
                    elseif ($line -match '^\s*server\s+(\S+)\s+(\S+)' -and $currentSection -eq "backend") {
                        $summary += "   • Server: $($matches[2])`n"
                    }
                }
                
                if (-not ($frontendFound -or $backendFound)) {
                    $summary += "No frontend or backend configurations found.`n"
                }
                
                $summary += "`n═══════════════════════════════════════`n"
                return $summary
            }
            else {
                return ($configLines -join "`n")
            }
        }
        Write-Host "Failed to read config file: $configLines"
        return "No configuration found"
    }
    catch {
        Write-Host "Exception reading config: $($_.Exception.Message)"
        Write-Error "Failed to read HAProxy configuration: $_"
        return "Error reading configuration"
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
    
    Write-Host "============================================"
    Write-Host "Applying HAProxy Configuration Changes:"
    Write-Host "============================================"
    Write-Host "Frontend Name   : $Frontend"
    Write-Host "Backend Name    : $Backend"
    Write-Host "Mode           : $Mode"
    Write-Host "Port           : $Port"
    Write-Host "Backend Servers : "
    foreach ($server in $BackendServers) {
        Write-Host "  • $server"
    }
    Write-Host "============================================"
    
    Write-Host "Creating new HAProxy config with:"
    Write-Host "Frontend: $Frontend"
    Write-Host "Backend: $Backend"
    Write-Host "Mode: $Mode"
    Write-Host "Port: $Port"
    Write-Host "Servers: $($BackendServers -join ', ')"
    
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
    Write-Host "Writing config to temp file: $tempFile"
    try {
        [System.IO.File]::WriteAllText($tempFile, $config)
        Write-Host "Successfully wrote temp file"
    }
    catch {
        Write-Host "Failed to write temp file: $($_.Exception.Message)"
        return $false
    }
    
    # Use sudo to move the file to its final location with proper permissions
    try {
        Write-Host "Moving temp file to: $ConfigPath"
        & sudo mv $tempFile $ConfigPath
        Write-Host "Setting ownership to haproxy:haproxy"
        & sudo chown haproxy:haproxy $ConfigPath
        Write-Host "Setting permissions to 644"
        & sudo chmod 644 $ConfigPath
        Write-Host "Successfully updated HAProxy config"
        return $true
    }
    catch {
        Write-Host "Failed to set permissions: $($_.Exception.Message)"
        Write-Error "Failed to set HAProxy configuration: $_"
        return $false
    }
}

function Test-HaproxyConfig {
    param(
        [string]$ConfigPath = '/etc/haproxy/haproxy.cfg'
    )
    
    try {
        Write-Host "Testing HAProxy config at: $ConfigPath"
        $result = & haproxy -c -f $ConfigPath 2>&1
        Write-Host "Test result exit code: $LASTEXITCODE"
        Write-Host "Test output: $result"
        return $LASTEXITCODE -eq 0
    }
    catch {
        Write-Host "Exception testing config: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Get-HaproxyConfig, Set-HaproxyConfig, Test-HaproxyConfig