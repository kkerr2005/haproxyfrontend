Import-Module Pode
Import-Module Pode.Web
$HaproxyUtilsPath = "$PSScriptRoot\HaproxyUtils.psm1"

Start-PodeServer {
    # Enable logging
    New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging

    # Add a web server on port 8080
    Add-PodeEndpoint -Address * -Port 8080 -Protocol Http
    
    # Enable session management
    Enable-PodeSessionMiddleware -Duration 120 -Extend

    # Set the use of Pode.Web
    Use-PodeWebtemplates -Title 'HAProxy Management' -Theme Dark

    # Add the navigation pages
    Add-PodeWebPage -Name 'Dashboard' -Icon 'dashboard' -ScriptBlock {
        try {
            Import-Module $using:HaproxyUtilsPath -ErrorAction Stop
            $config = Get-HaproxyConfig
            $configStatus = Test-HaproxyConfig

            New-PodeWebCard -Content @(
                New-PodeWebAlert -Type Info -Value 'Welcome to HAProxy Management Interface'
                New-PodeWebAlert -Type $(if ($configStatus) { 'Success' } else { 'Error' }) -Value "HAProxy Configuration Status: $(if ($configStatus) { 'Valid' } else { 'Invalid' })"
            )
        }
        catch {
            Write-PodeLog -Message $_.Exception.Message -Level Error
            New-PodeWebCard -Content @(
                New-PodeWebAlert -Type Error -Value "Error: $($_.Exception.Message)"
            )
        }
    }

    Add-PodeWebPage -Name 'Configuration' -Icon 'settings' -ScriptBlock {
        try {
            Import-Module $using:HaproxyUtilsPath -ErrorAction Stop
            
            New-PodeWebForm -Name 'haproxy-config' -Content @(
                New-PodeWebTextbox -Name 'Frontend' -Label 'Frontend Name' -Required
                New-PodeWebSelect -Name 'Mode' -Label 'Mode' -Options @('http', 'tcp') -Required
                New-PodeWebTextbox -Name 'Port' -Label 'Frontend Port' -Type Number -Required
                New-PodeWebTextbox -Name 'Backend' -Label 'Backend Name' -Required
                New-PodeWebTextbox -Name 'BackendServers' -Label 'Backend Servers (comma-separated)' -Required -PlaceHolder 'server1:port,server2:port'
            ) -ScriptBlock {
                param($Frontend, $Mode, $Port, $Backend, $BackendServers)
                
                try {
                    Import-Module $using:HaproxyUtilsPath -ErrorAction Stop
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
                    Write-PodeLog -Message $_.Exception.Message -Level Error
                    Show-PodeWebToast -Message "Error: $($_.Exception.Message)" -Type Error
                }
            }

            New-PodeWebCard -Content @(
                New-PodeWebCodeBlock -Value (Get-HaproxyConfig) -Language 'plaintext' -Title 'Current HAProxy Configuration'
            )
        }
        catch {
            Write-PodeLog -Message $_.Exception.Message -Level Error
            New-PodeWebCard -Content @(
                New-PodeWebAlert -Type Error -Value "Error: $($_.Exception.Message)"
            )
        }
    }
}