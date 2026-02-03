#!/bin/bash
# One-time setup for EC2 proxy instance to support ComfyUI reverse tunnels

set -e

echo "=== EC2 Proxy Setup for ComfyUI ==="

# Enable GatewayPorts for reverse SSH tunnels
if ! grep -q "^GatewayPorts yes" /etc/ssh/sshd_config; then
    echo "Enabling GatewayPorts in sshd_config..."
    sudo sed -i 's/#GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config
    sudo sed -i 's/GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config
    
    if ! grep -q "^GatewayPorts yes" /etc/ssh/sshd_config; then
        echo "GatewayPorts yes" | sudo tee -a /etc/ssh/sshd_config
    fi
    
    sudo systemctl restart sshd
    echo "sshd restarted with GatewayPorts enabled"
else
    echo "GatewayPorts already enabled"
fi

# Install socat if not present
if ! command -v socat &> /dev/null; then
    echo "Installing socat..."
    sudo yum install -y socat || sudo dnf install -y socat || sudo apt-get install -y socat
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To start the proxy, run:"
echo "  ./ec2-comfyui-proxy.sh"
