Import-Module Pode
Import-Module Pode.Web
$HaproxyUtilsPath = "$PSScriptRoot/HaproxyUtils.psm1"

Write-Host "Starting HAProxy Web Frontend"
Write-Host "Loading from: $HaproxyUtilsPath"

Start-PodeServer {
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
    Import-Module $HaproxyUtilsPath
    Write-Host "Module imported successfully"

    # Add the navigation pages
    Add-PodeWebPage -Name 'Dashboard' -Icon 'home' -ScriptBlock {
        Write-Host "Loading Dashboard page"
        try {
            Write-Host "Getting HAProxy config"
            $config = Get-HaproxyConfig -Simple
            Write-Host "Config retrieved:"
            Write-Host $config
            
            Write-Host "Testing config"
            $configStatus = Test-HaproxyConfig
            Write-Host "Config status: $configStatus"

            Write-Host "Building dashboard UI"
            New-PodeWebContainer -NoBackground -Content @(
                New-PodeWebCard -NoTitle -Content @(
                    New-PodeWebAlert -Type Info -Value 'Welcome to HAProxy Management Interface'
                    New-PodeWebAlert -Type $(if ($configStatus) { 'Success' } else { 'Failure' }) -Value "HAProxy Configuration Status: $(if ($configStatus) { 'Valid' } else { 'Invalid' })"
                )
                New-PodeWebCard -DisplayName 'Active Configuration' -Content @(
                    New-PodeWebText -Value $config
                )
            )
        }
        catch {
            Write-Host "Dashboard error: $($_.Exception.Message)"
            Write-Host "Stack trace: $($_.ScriptStackTrace)"
            New-PodeWebContainer -NoBackground -Content @(
                New-PodeWebCard -NoTitle -Content @(
                    New-PodeWebAlert -Type Failure -Value "Error: $($_.Exception.Message)"
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
                            Out-PodeWebToast -Message $errorMsg -Type Failure -Duration 5
                            return
                        }

                        # Type conversion validation
                        $portNumber = 0
                        if (-not [int]::TryParse($Port, [ref]$portNumber)) {
                            Write-Host "Invalid port number format"
                            Out-PodeWebToast -Message "Port must be a valid number" -Type Failure -Duration 5
                            return
                        }

                        Write-Host "All fields provided, proceeding with validation..."
                        
                        # Validate port range
                        if ($portNumber -lt 1 -or $portNumber -gt 65535) {
                            Write-Host "Port number out of range: $portNumber"
                            Out-PodeWebToast -Message "Port must be between 1 and 65535" -Type Failure -Duration 5
                            return
                        }

                        # Parse and validate backend servers
                        $servers = $BackendServers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                        Write-Host "Parsed servers: $($servers -join ', ')"
                        
                        if ($servers.Count -eq 0) {
                            Write-Host "No valid backend servers found"
                            Out-PodeWebToast -Message "Please provide at least one backend server in the format hostname:port" -Type Failure -Duration 5
                            return
                        }

                        foreach ($server in $servers) {
                            if (-not ($server -match '^[^:]+:\d+$')) {
                                Write-Host "Invalid server format: $server"
                                Out-PodeWebToast -Message "Invalid server format: $server. Must be hostname:port" -Type Failure -Duration 5
                                return
                            }
                            $serverPort = [int]($server -split ':')[1]
                            if ($serverPort -lt 1 -or $serverPort -gt 65535) {
                                Write-Host "Invalid server port: $serverPort"
                                Out-PodeWebToast -Message "Invalid port in server $server. Port must be between 1 and 65535" -Type Failure -Duration 5
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
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "HAProxy restarted successfully"
                                Out-PodeWebToast -Message "Configuration saved and HAProxy restarted successfully!" -Duration 5 -Type Success
                                Move-PodeWebUrl -Url "/dashboard"
                            }
                            else {
                                Write-Host "HAProxy restart failed: $restartResult"
                                Out-PodeWebToast -Message "Configuration saved but failed to restart HAProxy: $restartResult" -Duration 5 -Type Warning
                            }
                        }
                        else {
                            Write-Host "Config test failed"
                            throw "Invalid HAProxy configuration detected"
                        }
                    }
                    catch {
                        Write-Host "Error during configuration: $($_.Exception.Message)"
                        Write-Host "Stack trace: $($_.ScriptStackTrace)"
                        Out-PodeWebToast -Message "Configuration Error" -Duration 5 -Type Failure
                        Show-PodeWebError -Message $_.Exception.Message
                    }
                } -Content @(
                    New-PodeWebTextbox -Name 'Frontend' -Type Text -DisplayName 'Frontend Name' -Required -Placeholder 'e.g., web_frontend'
                    New-PodeWebSelect -Name 'Mode' -DisplayName 'Mode' -Options @('http', 'tcp') -Required
                    New-PodeWebTextbox -Name 'Port' -Type Number -DisplayName 'Frontend Port' -Required -Placeholder '80'
                    New-PodeWebTextbox -Name 'Backend' -Type Text -DisplayName 'Backend Name' -Required -Placeholder 'e.g., web_backend'
                    New-PodeWebTextbox -Name 'BackendServers' -Type Text -DisplayName 'Backend Servers' -Required -Placeholder 'server1:8080,server2:8080'
                ) -Submit 'Save Configuration' -AsCard

                New-PodeWebCard -DisplayName 'Current Configuration' -Content @(
                    New-PodeWebCode -Value (Get-HaproxyConfig)
                )
            )
        }
        catch {
            Write-Host "Configuration page error: $($_.Exception.Message)"
            Write-Host "Stack trace: $($_.ScriptStackTrace)"
            New-PodeWebContainer -NoBackground -Content @(
                New-PodeWebCard -NoTitle -Content @(
                    New-PodeWebAlert -Type Failure -Value "Error: $($_.Exception.Message)"
                )
            )
        }
    }

    Write-Host "Server configuration complete"
}