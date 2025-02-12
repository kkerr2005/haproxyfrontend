#!/bin/bash

# Exit on error
set -e

echo "Installing PowerShell and HAProxy prerequisites..."

# Update package list
sudo apt-get update

# Install prerequisites for PowerShell
sudo apt-get install -y \
    apt-transport-https \
    software-properties-common \
    wget \
    curl

# Download and install the Microsoft repository GPG key
wget -q "https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb"
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

# Update package list again after adding Microsoft repository
sudo apt-get update

# Install PowerShell
sudo apt-get install -y powershell

# Install HAProxy
sudo apt-get install -y haproxy

# Create HAProxy directories if they don't exist
sudo mkdir -p /etc/haproxy
sudo mkdir -p /var/lib/haproxy
sudo mkdir -p /run/haproxy

# Set proper permissions
sudo chown -R haproxy:haproxy /var/lib/haproxy
sudo chown -R haproxy:haproxy /run/haproxy

# Install Pode and Pode.Web modules for PowerShell
pwsh -Command "Install-Module -Name Pode -Force -AllowClobber"
pwsh -Command "Install-Module -Name Pode.Web -Force -AllowClobber"

# Create a backup of original HAProxy config
sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup

# Enable and start HAProxy service
sudo systemctl enable haproxy
sudo systemctl start haproxy

echo "Installation completed successfully!"
echo "PowerShell version:"
pwsh --version
echo "HAProxy version:"
haproxy -v
echo ""
echo "You can now run the Pode.Web HAProxy frontend using:"
echo "pwsh ./server.ps1"