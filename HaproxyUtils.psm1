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
    Write-Host "Config Path     : $ConfigPath"
    Write-Host "============================================"
    
    # Validate that we have at least one backend server
    if ($BackendServers.Count -eq 0) {
        Write-Host "Error: No backend servers provided"
        return $false
    }

    # Build configuration with explicit line endings
    $configLines = @(
        "global",
        "    log /dev/log local0",
        "    log /dev/log local1 notice",
        "    chroot /var/lib/haproxy",
        "    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners",
        "    stats timeout 30s",
        "    user haproxy",
        "    group haproxy",
        "    daemon",
        "    maxconn 4096",
        "",
        "defaults",
        "    log     global",
        "    mode    $Mode",
        "    option  ${Mode}log",
        "    option  dontlognull",
        "    retries 3",
        "    timeout connect 5000",
        "    timeout client  50000",
        "    timeout server  50000",
        "",
        "frontend $Frontend",
        "    bind *:$Port",
        "    mode $Mode",
        "    default_backend $Backend",
        "",
        "backend $Backend",
        "    mode $Mode",
        "    balance roundrobin",
        "    option ${Mode}close",
        "    option forwardfor"
    )

    # Add each backend server with a unique name
    $serverCount = 1
    foreach ($server in $BackendServers) {
        $serverName = $server.Split(':')[0]
        $configLines += "    server $($serverName.Replace('.', '-'))-$serverCount $server check"
        $serverCount++
    }

    # Join lines with Linux line endings and ensure final newline
    $config = $configLines -join "`n"
    $config += "`n"
    
    Write-Host "Generated config:"
    Write-Host "----------------------------------------"
    Write-Host $config
    Write-Host "----------------------------------------"
    
    # Write to a temporary file first
    $tempFile = "/tmp/haproxy.cfg.tmp"
    Write-Host "Writing config to temp file: $tempFile"
    try {
        [System.IO.File]::WriteAllText($tempFile, $config)
        if (Test-Path $tempFile) {
            Write-Host "Successfully wrote temp file. Content verification:"
            $verifyContent = Get-Content $tempFile -Raw
            Write-Host ($verifyContent -replace "`n", "[LF]")
        } else {
            Write-Host "Error: Temp file was not created!"
            return $false
        }
    }
    catch {
        Write-Host "Failed to write temp file: $($_.Exception.Message)"
        return $false
    }
    
    # Use sudo to move the file to its final location with proper permissions
    try {
        Write-Host "Moving temp file to: $ConfigPath"
        $moveResult = & sudo mv $tempFile $ConfigPath 2>&1
        Write-Host "Move command result: $moveResult"
        Write-Host "Move command exit code: $LASTEXITCODE"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Failed to move config file!"
            return $false
        }

        Write-Host "Setting ownership to haproxy:haproxy"
        $chownResult = & sudo chown haproxy:haproxy $ConfigPath 2>&1
        Write-Host "Chown command result: $chownResult"
        Write-Host "Chown command exit code: $LASTEXITCODE"

        Write-Host "Setting permissions to 644"
        $chmodResult = & sudo chmod 644 $ConfigPath 2>&1
        Write-Host "Chmod command result: $chmodResult"
        Write-Host "Chmod command exit code: $LASTEXITCODE"

        Write-Host "Verifying final config file:"
        if (Test-Path $ConfigPath) {
            Write-Host "Config file exists at: $ConfigPath"
            $finalContent = & sudo cat $ConfigPath 2>&1
            Write-Host "Final config content:"
            Write-Host ($finalContent -replace "`n", "[LF]")
            Write-Host "Successfully updated HAProxy config"
            return $true
        } else {
            Write-Host "Error: Final config file does not exist!"
            return $false
        }
    }
    catch {
        Write-Host "Failed during file operations: $($_.Exception.Message)"
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
        # First verify the file exists and has content
        if (-not (Test-Path $ConfigPath)) {
            Write-Host "Config file not found at: $ConfigPath"
            return $false
        }

        $fileContent = & sudo cat $ConfigPath 2>&1
        if (-not $fileContent) {
            Write-Host "Config file is empty"
            return $false
        }

        Write-Host "Config file content verification:"
        Write-Host "File exists and has content"

        # Now test the configuration
        Write-Host "Running HAProxy config test..."
        $result = & sudo haproxy -c -f $ConfigPath 2>&1
        Write-Host "Test result exit code: $LASTEXITCODE"
        Write-Host "Full test output:"
        $result | ForEach-Object { Write-Host "  $_" }
        
        if ($LASTEXITCODE -ne 0) {
            # Extract meaningful error message from HAProxy output
            $errorMessage = $result | Where-Object { $_ -match '^\[ALERT\]' } | ForEach-Object { 
                $_ -replace '^\[ALERT\]\s+\(\d+\)\s*:\s*', ''
            }
            
            if ($errorMessage) {
                Write-Error "HAProxy configuration error: $($errorMessage -join '; ')"
            }
            else {
                Write-Error "HAProxy configuration test failed with no specific error message"
            }
            return $false
        }
        
        Write-Host "Configuration test passed successfully"
        return $true
    }
    catch {
        Write-Host "Exception testing config: $($_.Exception.Message)"
        Write-Error $_.Exception.Message
        return $false
    }
}

Export-ModuleMember -Function Get-HaproxyConfig, Set-HaproxyConfig, Test-HaproxyConfig