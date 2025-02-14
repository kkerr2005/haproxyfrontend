# Module for HAProxy Configuration Management
$ModulePath = $PSScriptRoot

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

    try {
        Write-Host "Reading HAProxy config with sudo..."
        $configContent = & sudo cat $FilePath 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error reading config: $configContent"
            throw "Failed to read HAProxy configuration file"
        }

        $currentSection = ""
        $currentName = ""

        foreach ($line in $configContent) {
            $trimmedLine = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmedLine)) { continue }

            # Identify new section headers
            if ($trimmedLine -match "^(global|defaults|frontend|backend)\s*(\S*)?") {
                $currentSection = $matches[1]
                $currentName = $matches[2]

                if ($currentSection -eq "frontend") { $config.frontends[$currentName] = @() }
                elseif ($currentSection -eq "backend") { $config.backends[$currentName] = @() }
                
                Write-Host "Processing section: $currentSection $currentName"
            } 

            # Store section details
            if ($currentSection -eq "global" -or $currentSection -eq "defaults") {
                $config[$currentSection] += $trimmedLine
                Write-Host "Added to $currentSection : $trimmedLine"
            } elseif ($currentSection -eq "frontend" -and $currentName) {
                $config.frontends[$currentName] += $trimmedLine
                Write-Host "Added to frontend '$currentName': $trimmedLine"
            } elseif ($currentSection -eq "backend" -and $currentName) {
                $config.backends[$currentName] += $trimmedLine
                Write-Host "Added to backend '$currentName': $trimmedLine"
            }
        }
    }
    catch {
        Write-Host "Error in Convert-HAProxyConfig: $($_.Exception.Message)"
        Write-Host "Stack trace: $($_.ScriptStackTrace)"
        throw
    }

    Write-Host "Configuration parsing completed"
    return $config
}


