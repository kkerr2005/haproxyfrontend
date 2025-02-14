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


