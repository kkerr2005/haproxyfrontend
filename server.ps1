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
                New-PodeWebCard -Name 'Active Configuration' -Content @(
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
            Write-Host "Building configuration interface"
            New-PodeWebContainer -NoBackground -Content @(
                New-PodeWebCard -Name 'HAProxy Settings' -Content @(
                    # Frontend Table
                    New-PodeWebTable -Name 'Frontend_Settings' -DataColumn Name -SimpleSort -ScriptBlock {
                        $config = Get-HaproxyConfig
                        $frontendData = @(
                            [PSCustomObject]@{
                                Name = 'Frontend Name'
                                Value = $Frontend
                                Description = 'Name of the frontend service'
                                CanEdit = $true
                                ActionName = 'Frontend'
                            }
                            [PSCustomObject]@{
                                Name = 'Mode'
                                Value = $Mode
                                Description = 'Protocol mode (http/tcp)'
                                CanEdit = $true
                                ActionName = 'Mode'
                            }
                            [PSCustomObject]@{
                                Name = 'Port'
                                Value = $Port
                                Description = 'Frontend port (1-65535)'
                                CanEdit = $true
                                ActionName = 'Port'
                            }
                            [PSCustomObject]@{
                                Name = 'Backend Name'
                                Value = $Backend
                                Description = 'Name of the backend service'
                                CanEdit = $true
                                ActionName = 'Backend'
                            }
                        )
                        return $frontendData
                    } -Columns @(
                        New-PodeWebTableColumn -Name Value -Alignment Center
                        New-PodeWebTableColumn -Name Description
                    ) -Buttons @(
                        New-PodeWebTableButton -Name Edit -Icon Edit -ScriptBlock {
                            param($Value, $ActionName)
                            Show-PodeWebModal -Name "Edit_$ActionName" -DataValue $Value -ScriptBlock {
                                param($Value, $ActionName)
                                New-PodeWebForm -Name "EditForm_$ActionName" -Content @(
                                    New-PodeWebTextbox -Name 'NewValue' -Value $Value
                                ) -ScriptBlock {
                                    param($NewValue, $ActionName)
                                    # Update the configuration
                                    # Logic here to update specific setting
                                    Move-PodeWebUrl -Url '/configuration'
                                }
                            }
                        }
                    )

                    # Backend Servers Table
                    New-PodeWebTable -Name 'Backend_Servers' -DataColumn Server -SimpleSort -ScriptBlock {
                        $config = Get-HaproxyConfig
                        $backendServers = @()
                        $servers = $BackendServers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                        foreach ($server in $servers) {
                            $backendServers += [PSCustomObject]@{
                                Server = $server
                                Status = 'Active'
                                Action = $server
                            }
                        }
                        return $backendServers
                    } -Columns @(
                        New-PodeWebTableColumn -Name Status -Alignment Center
                    ) -Buttons @(
                        New-PodeWebTableButton -Name Edit -Icon Edit -ScriptBlock {
                            param($Value)
                            Show-PodeWebModal -Name 'EditServer' -DataValue $Value -ScriptBlock {
                                param($Value)
                                New-PodeWebForm -Name 'EditServerForm' -Content @(
                                    New-PodeWebTextbox -Name 'Server' -Value $Value
                                ) -ScriptBlock {
                                    param($Server)
                                    # Update server in configuration
                                    Move-PodeWebUrl -Url '/configuration'
                                }
                            }
                        }
                        New-PodeWebTableButton -Name Delete -Icon Trash -ScriptBlock {
                            param($Value)
                            # Remove server from configuration
                            Move-PodeWebUrl -Url '/configuration'
                        }
                    )

                    # Add New Server Button
                    New-PodeWebButton -Name 'Add Server' -Icon Plus -ScriptBlock {
                        Show-PodeWebModal -Name 'AddServer' -ScriptBlock {
                            New-PodeWebForm -Name 'AddServerForm' -Content @(
                                New-PodeWebTextbox -Name 'Server' -Type Text -Required -DisplayName 'Server Address:Port'
                            ) -ScriptBlock {
                                param($Server)
                                # Add new server to configuration
                                Move-PodeWebUrl -Url '/configuration'
                            }
                        }
                    }
                )

                # Current Configuration View
                New-PodeWebCard -Name 'Current Configuration' -Content @(
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