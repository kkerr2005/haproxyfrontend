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

# Create PowerShell profile directory
mkdir -p ~/.config/powershell
chmod 700 ~/.config/powershell

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

# Backup original HAProxy config
sudo mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.original

# Create new HAProxy config with the simplified format
cat << 'EOF' | sudo tee /etc/haproxy/haproxy.cfg
global
    log stdout format raw local0
    maxconn 4096
    daemon

defaults
    log global
    mode http
    timeout connect 5s
    timeout client 50s
    timeout server 50s

frontend http_front
    bind *:80
    default_backend web_servers

backend web_servers
    balance roundrobin
    server server1 192.168.1.101:80 check
    server server2 192.168.1.102:80 check

EOF

# Ensure proper line ending
echo "" | sudo tee -a /etc/haproxy/haproxy.cfg

# Set proper permissions on new config
sudo chown haproxy:haproxy /etc/haproxy/haproxy.cfg
sudo chmod 644 /etc/haproxy/haproxy.cfg

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