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
                    Write-Host "Processing submission with values:"
                    Write-Host "Frontend Name : [$Frontend]"
                    Write-Host "Mode         : [$Mode]"
                    Write-Host "Port         : [$Port]"
                    Write-Host "Backend Name : [$Backend]"
                    Write-Host "Servers      : [$BackendServers]"
                    Write-Host "===================================================="
                    
                    try {
                        Write-Host "Step 1: Validating input parameters"
                        if ([string]::IsNullOrEmpty($Frontend) -or 
                            [string]::IsNullOrEmpty($Mode) -or 
                            [string]::IsNullOrEmpty($Backend) -or 
                            [string]::IsNullOrEmpty($BackendServers)) {
                            throw "All fields are required. Please check your input."
                        }

                        if (-not [int]::TryParse($Port, [ref]$null)) {
                            throw "Port must be a valid number"
                        }

                        Write-Host "Step 2: Processing backend servers string"
                        $servers = $BackendServers -split ',' | ForEach-Object { $_.Trim() }
                        if ($servers.Count -eq 0) {
                            throw "No valid backend servers provided"
                        }
                        Write-Host "Parsed servers: $($servers -join ', ')"
                        
                        Write-Host "Step 3: Checking config path accessibility"
                        $configPath = '/etc/haproxy/haproxy.cfg'
                        $testPath = & sudo test -w $configPath 2>&1
                        $pathAccessible = $LASTEXITCODE -eq 0
                        Write-Host "Config path accessible: $pathAccessible"
                        
                        if (-not $pathAccessible) {
                            Write-Host "Config path not accessible: $configPath"
                            throw "Cannot access HAProxy config at $configPath. Check permissions."
                        }
                        
                        Write-Host "Step 4: Setting HAProxy config"
                        $configSet = Set-HaproxyConfig -Frontend $Frontend -Backend $Backend -BackendServers $servers -Mode $Mode -Port $Port
                        
                        if (-not $configSet) {
                            throw "Failed to set HAProxy configuration"
                        }
                        
                        Write-Host "Step 5: Testing new configuration"
                        $configValid = Test-HaproxyConfig
                        Write-Host "Config test result: $configValid"
                        
                        if ($configValid) {
                            Write-Host "Step 6: Restarting HAProxy service"
                            try {
                                $restartResult = & sudo systemctl restart haproxy 2>&1
                                $restartSuccess = $LASTEXITCODE -eq 0
                                Write-Host "Restart command result: $restartResult"
                                Write-Host "Restart exit code: $LASTEXITCODE"
                                
                                if ($restartSuccess) {
                                    Write-Host "HAProxy restart successful"
                                    Out-PodeWebToast -Message "Configuration saved and HAProxy restarted successfully!" -Duration 5 -Type Success
                                    
                                    # Refresh the page to show new config
                                    Sync-PodeWebWindow
                                }
                                else {
                                    Write-Host "HAProxy restart failed"
                                    Out-PodeWebToast -Message "Configuration saved but failed to restart HAProxy: $restartResult" -Duration 5 -Type Warning
                                }
                            }
                            catch {
                                Write-Host "Exception during restart: $($_.Exception.Message)"
                                Out-PodeWebToast -Message "Error during restart: $($_.Exception.Message)" -Duration 5 -Type Warning
                            }
                        }
                        else {
                            Write-Host "Config test failed"
                            Out-PodeWebToast -Message "Invalid configuration detected!" -Duration 5 -Type Failure
                        }
                    }
                    catch {
                        Write-Host "Error during configuration: $($_.Exception.Message)"
                        Write-Host "Stack trace: $($_.ScriptStackTrace)"
                        Out-PodeWebToast -Message "Error: $($_.Exception.Message)" -Duration 5 -Type Failure
                    }
                } -Content @(
                    New-PodeWebTextbox -Name 'Frontend' -Type Text -DisplayName 'Frontend Name' -Required
                    New-PodeWebSelect -Name 'Mode' -DisplayName 'Mode' -Options @('http', 'tcp') -Required
                    New-PodeWebTextbox -Name 'Port' -Type Number -DisplayName 'Frontend Port' -Required
                    New-PodeWebTextbox -Name 'Backend' -Type Text -DisplayName 'Backend Name' -Required
                    New-PodeWebTextbox -Name 'BackendServers' -Type Text -DisplayName 'Backend Servers' -Placeholder 'server1:port,server2:port' -Required
                ) -Submit 'Save Configuration'

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