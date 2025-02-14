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
        New-PodeWebAlert -Type $Type -Value $Message
    }
    catch {
        Write-Host "Failed to show message: $($_.Exception.Message)"
        # Fallback to basic alert if something goes wrong
        New-PodeWebAlert -Type Error -Value $Message
    }
}

Write-Host "Starting HAProxy Web Frontend"
Write-Host "Loading from: $HaproxyUtilsPath"

Start-PodeServer {
    # Import required modules
    Import-Module $HaproxyUtilsPath -Force
    
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
            $config = Get-HaproxyConfig -Simple "/etc/haproxy/haproxy.cfg"
            Write-Host "Config retrieved"
            
            # Convert the config to structured format
            $structuredConfig = Convert-HAProxyConfig -FilePath "/etc/haproxy/haproxy.cfg"
            
            if ($null -eq $structuredConfig -or 
                $null -eq $structuredConfig.global -or 
                $null -eq $structuredConfig.defaults -or 
                $null -eq $structuredConfig.frontends -or 
                $null -eq $structuredConfig.backends) {
                throw "Failed to parse HAProxy configuration. The configuration structure is invalid or empty."
            }
write-host "Here is the config"
            $structuredConfig.GetEnumerator() | out-string
            
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

                # Add structured configuration display
                New-PodeWebCard -Name 'HAProxy Configuration Details' -Content @(
                    New-PodeWebText -Value 'Global Settings'
                    New-PodeWebList -Items $structuredConfig.global

                    New-PodeWebText -Value 'Default Settings'
                    New-PodeWebList -Items $structuredConfig.defaults

                    foreach ($frontend in $structuredConfig.frontends.Keys) {
                        New-PodeWebText -Value "Frontend: $frontend"
                        New-PodeWebList -Items $structuredConfig.frontends[$frontend]
                    }

                    foreach ($backend in $structuredConfig.backends.Keys) {
                        New-PodeWebText -Value "Backend: $backend"
                        New-PodeWebList -Items $structuredConfig.backends[$backend]
                    }
                )

                New-PodeWebCard -Name 'Active Configuration' -Content @(
                    New-PodeWebForm -Name 'ConfigForm' -Content @(
                        New-PodeWebCard -Name 'Frontend Configuration' -Content @(
                            New-PodeWebTextbox -Name 'Frontend' -Value $config.Frontend -DisplayName 'Frontend Name'
                            New-PodeWebTextbox -Name 'Port' -Value $config.Port -DisplayName 'Port'
                            New-PodeWebSelect -Name 'Mode' -Options @('http', 'tcp') -SelectedValue $config.Mode -DisplayName 'Mode'
                        )
                        New-PodeWebCard -Name 'Backend Configuration' -Content @(
                            New-PodeWebTextbox -Name 'Backend' -Value $config.Backend -DisplayName 'Backend Name'
                            New-PodeWebTextbox -Name 'BackendServers' -Value $config.BackendServers -DisplayName 'Backend Servers (comma-separated)'
                        )
                    ) -ScriptBlock {
                        param($Frontend, $Backend, $BackendServers, $Mode, $Port)
                        Set-HaproxyConfig -Frontend $Frontend -Backend $Backend -BackendServers $BackendServers -Mode $Mode -Port $Port
                        Show-UserMessage -Message "Configuration updated successfully!" -Type Success
                        Move-PodeWebUrl -Url '/dashboard'
                    }
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

}

