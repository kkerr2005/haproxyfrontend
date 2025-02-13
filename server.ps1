Import-Module Pode
Import-Module Pode.Web
$HaproxyUtilsPath = "$PSScriptRoot/HaproxyUtils.psm1"

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

            New-PodeWebContainer -NoBackground -Content @(
                New-PodeWebCard -NoTitle -Content @(
                    New-PodeWebAlert -Type Info -Value 'Welcome to HAProxy Management Interface'
                    New-PodeWebAlert -Type $(if ($configStatus) { 'Success' } else { 'Failure' }) -Value "HAProxy Configuration Status: $(if ($configStatus) { 'Valid' } else { 'Invalid' })"
                )
                New-PodeWebCard -Title 'Current Configuration' -Content @(
                    New-PodeWebCode -Value $config -Language 'powershell'
                )
            )
        }
        catch {
            New-PodeWebContainer -NoBackground -Content @(
                New-PodeWebCard -NoTitle -Content @(
                    New-PodeWebAlert -Type Failure -Value "Error: $($_.Exception.Message)"
                )
            )
        }
    }

#     Add-PodeWebPage -Name 'Configuration' -Icon 'settings' -ScriptBlock {
#         try {
#             New-PodeWebContainer -NoBackground -Content @(
#                 New-PodeWebForm -Name 'haproxy-config' -ScriptBlock {
#                     param($Frontend, $Mode, $Port, $Backend, $BackendServers)
                    
#                     try {
#                         $servers = $BackendServers -split ',' | ForEach-Object { $_.Trim() }
                        
#                         # Check if we have permission to write to config
#                         $configPath = '/etc/haproxy/haproxy.cfg'
#                         if (-not (Test-Path $configPath -ErrorAction SilentlyContinue)) {
#                             throw "Cannot access HAProxy config at $configPath. Check permissions."
#                         }
                        
#                         Set-HaproxyConfig -Frontend $Frontend -Backend $Backend -BackendServers $servers -Mode $Mode -Port $Port
                        
#                         if (Test-HaproxyConfig) {
#                             # Use systemctl command directly for Linux
#                             $restartResult = $null
#                             try {
#                                 $restartResult = & sudo systemctl restart haproxy 2>&1
#                                 Out-PodeWebToast -Message "Configuration saved and HAProxy restarted successfully!" -Duration 5 -Type Success
#                             }
#                             catch {
#                                 Out-PodeWebToast -Message "Configuration saved but failed to restart HAProxy: $restartResult" -Duration 5 -Type Warning
#                             }
#                         }
#                         else {
#                             Out-PodeWebToast -Message "Invalid configuration detected!" -Duration 5 -Type Failure
#                         }
#                     }
#                     catch {
#                         Out-PodeWebToast -Message "Error: $($_.Exception.Message)" -Duration 5 -Type Failure
#                     }
#                 } -Content @(
#                     New-PodeWebTextbox -Name 'Frontend' -Type Text -DisplayName 'Frontend Name' -Required
#                     New-PodeWebSelect -Name 'Mode' -DisplayName 'Mode' -Options @('http', 'tcp') -Required
#                     New-PodeWebTextbox -Name 'Port' -Type Number -DisplayName 'Frontend Port' -Required
#                     New-PodeWebTextbox -Name 'Backend' -Type Text -DisplayName 'Backend Name' -Required
#                     New-PodeWebTextbox -Name 'BackendServers' -Type Text -DisplayName 'Backend Servers' -Placeholder 'server1:port,server2:port' -Required
#                 ) -Actions @(
#                     New-PodeWebFormAction -Name 'Save' -ActionValue 'Save Configuration'
#                 )

#                 New-PodeWebCard -Title 'Current Configuration' -Content @(
#                     New-PodeWebCode -Value (Get-HaproxyConfig) -Language 'powershell'
#                 )
#             )
#         }
#         catch {
#             New-PodeWebContainer -NoBackground -Content @(
#                 New-PodeWebCard -NoTitle -Content @(
#                     New-PodeWebAlert -Type Failure -Value "Error: $($_.Exception.Message)"
#                 )
#             )
#         }
#     }
# }