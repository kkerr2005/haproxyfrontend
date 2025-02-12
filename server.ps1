Import-Module Pode
Import-Module Pode.Web
$HaproxyUtilsPath = "$PSScriptRoot\HaproxyUtils.psm1"

Start-PodeServer {
    # Add a web server on port 8080
    Add-PodeEndpoint -Address * -Port 8080 -Protocol Http
    
    # Enable session management
    Enable-PodeSessionMiddleware -Duration 120 -Extend

    # Set the use of Pode.Web
    Use-PodeWebTemplates -Title 'HAProxy Management' -Theme Dark

    # Import the module at server startup
    Import-Module $HaproxyUtilsPath

    # Add the navigation pages
    Add-PodeWebPage -Name 'Dashboard' -Icon 'home' -ScriptBlock {
        try {
            $config = Get-HaproxyConfig
            $configStatus = Test-HaproxyConfig

            New-PodeWebContainer -Content @(
                New-PodeWebCard -Content @(
                    New-PodeWebAlert -Type Info -Value 'Welcome to HAProxy Management Interface'
                    New-PodeWebAlert -Type $(if ($configStatus) { 'Success' } else { 'Error' }) -Value "HAProxy Configuration Status: $(if ($configStatus) { 'Valid' } else { 'Invalid' })"
                ),
                New-PodeWebCard -Title 'Current Configuration' -Content @(
                    New-PodeWebCodeBlock -Value $config -Language 'plaintext'
                )
            )
        }
        catch {
            New-PodeWebContainer -Content @(
                New-PodeWebCard -Content @(
                    New-PodeWebAlert -Type Error -Value "Error: $($_.Exception.Message)"
                )
            )
        }
    }

    Add-PodeWebPage -Name 'Configuration' -Icon 'settings' -ScriptBlock {
        try {
            New-PodeWebContainer -Content @(
                New-PodeWebForm -Name 'haproxy-config' -Content @(
                    New-PodeWebTextbox -Name 'Frontend' -DisplayName 'Frontend Name' -Required
                    New-PodeWebSelect -Name 'Mode' -DisplayName 'Mode' -Options @('http', 'tcp') -Required
                    New-PodeWebTextbox -Name 'Port' -DisplayName 'Frontend Port' -Type Number -Required
                    New-PodeWebTextbox -Name 'Backend' -DisplayName 'Backend Name' -Required
                    New-PodeWebTextbox -Name 'BackendServers' -DisplayName 'Backend Servers' -Required -PlaceHolder 'server1:port,server2:port'
                ) -ScriptBlock {
                    param($Frontend, $Mode, $Port, $Backend, $BackendServers)
                    
                    try {
                        $servers = $BackendServers -split ',' | ForEach-Object { $_.Trim() }
                        
                        # Check if we have permission to write to config
                        $configPath = '/etc/haproxy/haproxy.cfg'
                        if (-not (Test-Path $configPath -ErrorAction SilentlyContinue)) {
                            throw "Cannot access HAProxy config at $configPath. Check permissions."
                        }
                        
                        Set-HaproxyConfig -Frontend $Frontend -Backend $Backend -BackendServers $servers
                        
                        if (Test-HaproxyConfig) {
                            # Use sudo with password-less configuration for haproxy restart
                            $restartResult = Start-Process 'sudo' -ArgumentList 'systemctl restart haproxy' -Wait -PassThru
                            if ($restartResult.ExitCode -eq 0) {
                                Show-PodeWebToast -Message "Configuration saved and HAProxy restarted successfully!" -Type Success
                            }
                            else {
                                Show-PodeWebToast -Message "Configuration saved but failed to restart HAProxy" -Type Warning
                            }
                        }
                        else {
                            Show-PodeWebToast -Message "Invalid configuration detected!" -Type Error
                        }
                    }
                    catch {
                        Show-PodeWebToast -Message "Error: $($_.Exception.Message)" -Type Error
                    }
                }

                New-PodeWebCard -Title 'Current Configuration' -Content @(
                    New-PodeWebCodeBlock -Value (Get-HaproxyConfig) -Language 'plaintext'
                )
            )
        }
        catch {
            New-PodeWebContainer -Content @(
                New-PodeWebCard -Content @(
                    New-PodeWebAlert -Type Error -Value "Error: $($_.Exception.Message)"
                )
            )
        }
    }
}