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
                $currentMode = "http"
                
                foreach ($line in $configLines) {
                    $line = $line.Trim()
                    
                    # Get mode from defaults section
                    if ($line -match '^\s*mode\s+(\S+)' -and $currentSection -eq "defaults") {
                        $currentMode = $matches[1]
                    }
                    # Track current section
                    elseif ($line -match '^(global|defaults|frontend|backend)\s*(\S*)') {
                        $currentSection = $matches[1]
                        if ($matches[2]) {
                            if ($currentSection -eq "frontend") {
                                $summary += "`n► FRONTEND: $($matches[2])`n"
                                $summary += "   Mode: $currentMode`n"
                            }
                            elseif ($currentSection -eq "backend") {
                                $summary += "`n► BACKEND: $($matches[2])`n"
                            }
                        }
                    }
                    # Get port from bind directive
                    elseif ($line -match '^\s*bind\s+\*:(\d+)' -and $currentSection -eq "frontend") {
                        $summary += "   Port: $($matches[1])`n"
                    }
                    # Get backend servers
                    elseif ($line -match '^\s*server\s+(\S+)\s+(\S+)' -and $currentSection -eq "backend") {
                        $summary += "   • Server: $($matches[2])`n"
                    }
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

    # Build configuration sections
    $globalSection = @(
        "global",
        "    log stdout format raw local0",
        "    maxconn 4096",
        "    daemon"
    )

    $defaultsSection = @(
        "defaults",
        "    log global",
        "    mode $Mode",
        "    timeout connect 5s",
        "    timeout client 50s",
        "    timeout server 50s"
    )

    $frontendSection = @(
        "frontend $Frontend",
        "    bind *:$Port",
        "    default_backend $Backend"
    )

    $backendSection = @(
        "backend $Backend",
        "    balance roundrobin"
    )

    # Add each backend server with proper indentation
    $serverCount = 1
    foreach ($server in $BackendServers) {
        $backendSection += "    server server$serverCount $server check"
        $serverCount++
    }

    # Join all sections with double newlines between them
    $configLines = @(
        $globalSection -join "`n",
        "",
        $defaultsSection -join "`n",
        "",
        $frontendSection -join "`n",
        "",
        $backendSection -join "`n",
        "" # Ensure final newline
    )

    # Create final config with Unix line endings
    $config = ($configLines -join "`n").Replace("`r`n", "`n")
    
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
        if (-not (Test-Path $ConfigPath)) {
            Write-Host "Config file not found at: $ConfigPath"
            return $false
        }

        # First verify the file has proper line endings and structure
        $content = Get-Content $ConfigPath -Raw
        
        # Check for basic structure
        if (-not ($content -match 'global\s')) {
            Write-Host "Error: Missing 'global' section"
            return $false
        }
        if (-not ($content -match 'defaults\s')) {
            Write-Host "Error: Missing 'defaults' section"
            return $false
        }
        if (-not ($content -match 'frontend\s')) {
            Write-Host "Error: Missing 'frontend' section"
            return $false
        }
        if (-not ($content -match 'backend\s')) {
            Write-Host "Error: Missing 'backend' section"
            return $false
        }

        # Fix line endings if needed
        if ($content -and -not $content.EndsWith("`n")) {
            Write-Host "Config file is missing final newline, attempting to fix..."
            $content = $content.TrimEnd() + "`n"
            try {
                $tempFile = "/tmp/haproxy.cfg.tmp"
                [System.IO.File]::WriteAllText($tempFile, $content)
                & sudo mv $tempFile $ConfigPath
                & sudo chown haproxy:haproxy $ConfigPath
                & sudo chmod 644 $ConfigPath
                Write-Host "Fixed line endings in config file"
            }
            catch {
                Write-Host "Failed to fix line endings: $($_.Exception.Message)"
            }
        }

        Write-Host "Running HAProxy config test..."
        $output = & sudo haproxy -c -f $ConfigPath 2>&1
        $exitCode = $LASTEXITCODE
        
        Write-Host "Test result exit code: $exitCode"
        Write-Host "Full test output:"
        if ($output -is [array]) {
            $output | ForEach-Object { Write-Host "  $_" }
        } else {
            Write-Host "  $output"
        }
        
        if ($exitCode -eq 0) {
            Write-Host "Configuration test passed successfully"
            return $true
        } else {
            Write-Host "Configuration test failed"
            if ($output -match "Missing LF") {
                Write-Host "Line ending issue detected, attempting to fix..."
                try {
                    $content = (Get-Content $ConfigPath -Raw).TrimEnd() + "`n"
                    $tempFile = "/tmp/haproxy.cfg.tmp"
                    [System.IO.File]::WriteAllText($tempFile, $content)
                    & sudo mv $tempFile $ConfigPath
                    & sudo chown haproxy:haproxy $ConfigPath
                    & sudo chmod 644 $ConfigPath
                    
                    # Test again after fixing
                    Write-Host "Retesting configuration after fixing line endings..."
                    $output = & sudo haproxy -c -f $ConfigPath 2>&1
                    $exitCode = $LASTEXITCODE
                    
                    if ($exitCode -eq 0) {
                        Write-Host "Configuration test passed after fixing line endings"
                        return $true
                    }
                }
                catch {
                    Write-Host "Failed to fix line endings: $($_.Exception.Message)"
                }
            }
            return $false
        }
    }
    catch {
        Write-Host "Exception testing config: $($_.Exception.Message)"
        return $false
    }
}

function Convert-HAProxyConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    # Initialize structured configuration object
    $config = @{
        global = @()
        defaults = @()
        frontends = @{}
        backends = @{}
    }

    $currentSection = ""
    $currentName = ""

    foreach ($line in Get-Content $FilePath) {
        $trimmedLine = $line.Trim()

        # Identify new section headers
        if ($trimmedLine -match "^(global|defaults|frontend|backend)\s+(\S*)?") {
            $currentSection = $matches[1]
            $currentName = $matches[2]

            if ($currentSection -eq "frontend") { $config.frontends[$currentName] = @() }
            elseif ($currentSection -eq "backend") { $config.backends[$currentName] = @() }
        } 

        # Store section details
        if ($currentSection -eq "global" -or $currentSection -eq "defaults") {
            $config[$currentSection] += $trimmedLine
        } elseif ($currentSection -eq "frontend") {
            $config.frontends[$currentName] += $trimmedLine
        } elseif ($currentSection -eq "backend") {
            $config.backends[$currentName] += $trimmedLine
        }
    }

    return $config
}

Export-ModuleMember -Function Get-HaproxyConfig, Set-HaproxyConfig, Test-HaproxyConfig, Convert-HAProxyConfig