Import-Module Pode -Force
Import-Module Pode.Web -Force
$HaproxyUtilsPath = "$PSScriptRoot/HaproxyUtils.psm1"

# Helper function to show consistent alerts
function Show-UserMessage {
    param(
        [string]$Message,
        [string]$Type = 'Info'
    )
    
    try {
        Write-Host "Showing message: $Message (Type: $Type)"
        Show-PodeWebAlert -Type $Type -Value $Message
    }
    catch {
        Write-Host "Failed to show message: $($_.Exception.Message)"
        # Fallback to basic alert if something goes wrong
        Show-PodeWebAlert -Type Error -Value $Message
    }
}

Write-Host "Starting HAProxy Web Frontend"
Write-Host "Loading from: $HaproxyUtilsPath"

Start-PodeServer {
    # Check HAProxy installation first
    try {
        $haproxyBinary = & sudo which haproxy 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: HAProxy is not installed or not accessible"
            Write-Host "Please run install.sh first to set up the prerequisites"
            throw "HAProxy not found. Please install HAProxy first."
        }
        Write-Host "Found HAProxy at: $haproxyBinary"
    }
    catch {
        Write-Host "Error checking HAProxy installation: $($_.Exception.Message)"
        throw "Failed to verify HAProxy installation. Error: $($_.Exception.Message)"
    }

    # Add a web server on port 8080
    Add-PodeEndpoint -Address * -Port 8080 -Protocol Http
    Write-Host "Added endpoint: http://*:8080"
    
    # Enable session management
    Enable-PodeSessionMiddleware -Duration 120 -Extend
    Write-Host "Enabled session middleware"

    # Set the use of Pode.Web
    Use-PodeWebTemplates -Title 'HAProxy Management' -Theme Dark
    Write-Host "Initialized Pode.Web templates"

    # Import the module at server startup
    Write-Host "Importing HaproxyUtils module"
    Import-Module $HaproxyUtilsPath -Force
    Write-Host "Module imported successfully"

    # Add the navigation pages
    Add-PodeWebPage -Name 'Dashboard' -Icon 'home' -ScriptBlock {
        Write-Host "Loading Dashboard page"
        try {
            Write-Host "Getting HAProxy config"
            $config = Get-HaproxyConfig -Simple
            Write-Host "Config retrieved"
            
            Write-Host "Testing config"
            $configResult = Test-HaproxyConfig
            Write-Host "Config status: $configResult"

            # Check HAProxy service status
            $serviceStatus = & sudo systemctl is-active haproxy 2>&1
            $isRunning = $LASTEXITCODE -eq 0
            Write-Host "HAProxy service status: $serviceStatus"

            Write-Host "Building dashboard UI"
            New-PodeWebContainer -NoBackground -Content @(
                New-PodeWebCard -NoTitle -Content @(
                    New-PodeWebAlert -Type Info -Value 'Welcome to HAProxy Management Interface'
                    New-PodeWebAlert -Type $(if ($configResult) { 'Success' } else { 'Error' }) -Value "HAProxy Configuration Status: $(if ($configResult) { 'Valid' } else { 'Invalid' })"
                    New-PodeWebAlert -Type $(if ($isRunning) { 'Success' } else { 'Warning' }) -Value "HAProxy Service Status: $serviceStatus"
                )
                New-PodeWebCard -Title 'Active Configuration' -Content @(
                    New-PodeWebText -Value $config
                )
            )
        }
        catch {
            Write-Host "Dashboard error: $($_.Exception.Message)"
            Write-Host "Stack trace: $($_.ScriptStackTrace)"
            New-PodeWebContainer -NoBackground -Content @(
                New-PodeWebCard -NoTitle -Content @(
                    New-PodeWebAlert -Type Error -Value "Error: $($_.Exception.Message)"
                )
            )
        }
    }

    Add-PodeWebPage -Name 'Configuration' -Icon 'settings' -ScriptBlock {
        Write-Host "Loading Configuration page"
        try {
            Write-Host "Building configuration form"
            New-PodeWebContainer -NoBackground -Content @(
                New-PodeWebForm -Name 'haproxy-config' -ScriptBlock {
                    param($Frontend, $Mode, $Port, $Backend, $BackendServers)
                    
                    Write-Host "===================================================="
                    Write-Host "Form Submission Received - HAProxy Configuration"
                    Write-Host "===================================================="
                    Write-Host "RAW VALUES RECEIVED:"
                    Write-Host "Frontend Name : '$Frontend'"
                    Write-Host "Mode         : '$Mode'"
                    Write-Host "Port         : '$Port'"
                    Write-Host "Backend Name : '$Backend'"
                    Write-Host "Servers      : '$BackendServers'"
                    Write-Host "===================================================="
                    
                    try {
                        # Initial validation with detailed messages
                        $missingFields = @()
                        if ([string]::IsNullOrWhiteSpace($Frontend)) { $missingFields += "Frontend Name" }
                        if ([string]::IsNullOrWhiteSpace($Mode)) { $missingFields += "Mode" }
                        if ([string]::IsNullOrWhiteSpace($Port)) { $missingFields += "Port" }
                        if ([string]::IsNullOrWhiteSpace($Backend)) { $missingFields += "Backend Name" }
                        if ([string]::IsNullOrWhiteSpace($BackendServers)) { $missingFields += "Backend Servers" }

                        if ($missingFields.Count -gt 0) {
                            $errorMsg = "Missing required fields: $($missingFields -join ', ')"
                            Write-Host "Validation Error: $errorMsg"
                            Show-UserMessage -Message $errorMsg -Type Warning
                            return
                        }

                        # Type conversion validation
                        $portNumber = 0
                        if (-not [int]::TryParse($Port, [ref]$portNumber)) {
                            Write-Host "Invalid port number format"
                            Show-UserMessage -Message "Port must be a valid number" -Type Warning
                            return
                        }
                        
                        # Validate port range
                        if ($portNumber -lt 1 -or $portNumber -gt 65535) {
                            Write-Host "Port number out of range: $portNumber"
                            Show-UserMessage -Message "Port must be between 1 and 65535" -Type Warning
                            return
                        }

                        # Parse and validate backend servers
                        $servers = $BackendServers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                        Write-Host "Parsed servers: $($servers -join ', ')"
                        
                        if ($servers.Count -eq 0) {
                            Write-Host "No valid backend servers found"
                            Show-UserMessage -Message "Please provide at least one backend server in the format hostname:port" -Type Warning
                            return
                        }

                        foreach ($server in $servers) {
                            if (-not ($server -match '^[^:]+:\d+$')) {
                                Write-Host "Invalid server format: $server"
                                Show-UserMessage -Message "Invalid server format: $server. Must be hostname:port" -Type Warning
                                return
                            }
                            $serverPort = [int]($server -split ':')[1]
                            if ($serverPort -lt 1 -or $serverPort -gt 65535) {
                                Write-Host "Invalid server port: $serverPort"
                                Show-UserMessage -Message "Invalid port in server $server. Port must be between 1 and 65535" -Type Warning
                                return
                            }
                        }

                        Write-Host "All validation passed, proceeding with configuration..."
                        
                        # Set the configuration
                        $configSet = Set-HaproxyConfig -Frontend $Frontend -Backend $Backend -BackendServers $servers -Mode $Mode -Port $portNumber
                        
                        if (-not $configSet) {
                            throw "Failed to set HAProxy configuration"
                        }
                        
                        Write-Host "Testing new configuration"
                        if (Test-HaproxyConfig) {
                            Write-Host "Config test passed, restarting HAProxy"
                            $restartResult = & sudo systemctl restart haproxy 2>&1
                            $restartSuccess = $LASTEXITCODE -eq 0
                            Write-Host "Restart command result: $restartResult"
                            Write-Host "Restart exit code: $LASTEXITCODE"

                            if ($restartSuccess) {
                                Write-Host "HAProxy restarted successfully"
                                Show-UserMessage -Message "Configuration saved and HAProxy restarted successfully!" -Type Success
                                
                                # Verify service is actually running after restart
                                $serviceStatus = & sudo systemctl is-active haproxy 2>&1
                                if ($LASTEXITCODE -ne 0) {
                                    Show-UserMessage -Message "Warning: HAProxy service is not running after restart. Status: $serviceStatus" -Type Warning
                                }
                                
                                Move-PodeWebUrl -Url "/dashboard"
                            }
                            else {
                                Write-Host "HAProxy restart failed: $restartResult"
                                Show-UserMessage -Message "Configuration saved but failed to restart HAProxy: $restartResult" -Type Warning
                            }
                        }
                        else {
                            Write-Host "Config test failed"
                            Show-UserMessage -Message "HAProxy configuration test failed. Please check the configuration." -Type Error
                            return
                        }
                    }
                    catch {
                        Write-Host "Error during configuration: $($_.Exception.Message)"
                        Write-Host "Stack trace: $($_.ScriptStackTrace)"
                        Show-UserMessage -Message "Configuration Error: $($_.Exception.Message)" -Type Error
                    }
                } -Content @(
                    New-PodeWebTextbox -Name 'Frontend' -Type Text -DisplayName 'Frontend Name' -Required
                    New-PodeWebSelect -Name 'Mode' -DisplayName 'Mode' -Options @('http', 'tcp') -Required
                    New-PodeWebTextbox -Name 'Port' -Type Number -DisplayName 'Frontend Port' -Required
                    New-PodeWebTextbox -Name 'Backend' -Type Text -DisplayName 'Backend Name' -Required
                    New-PodeWebTextbox -Name 'BackendServers' -Type Text -DisplayName 'Backend Servers' -Required
                ) -Submit 'Save Configuration'

                New-PodeWebCard -Title 'Current Configuration' -Content @(
                    New-PodeWebText -Value (Get-HaproxyConfig)
                )
            )
        }
        catch {
            Write-Host "Configuration page error: $($_.Exception.Message)"
            Write-Host "Stack trace: $($_.ScriptStackTrace)"
            New-PodeWebContainer -NoBackground -Content @(
                New-PodeWebCard -NoTitle -Content @(
                    New-PodeWebAlert -Type Error -Value "Error: $($_.Exception.Message)"
                )
            )
        }
    }
}