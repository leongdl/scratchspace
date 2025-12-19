#!/bin/bash
# EC2 Instance Setup Script
# Run this on the EC2 proxy instance to install dependencies and configure the reverse proxy

set -e

echo "=============================================="
echo "EC2 Proxy Instance Setup"
echo "=============================================="

# Install required packages
echo "Installing required packages..."
sudo yum install -y socat openssh-server || sudo dnf install -y socat openssh-server

# Enable and start SSH server (needed for reverse SSH from Deadline worker)
echo "Configuring SSH server..."
sudo systemctl enable sshd
sudo systemctl start sshd

# Configure SSH to allow reverse tunnels
echo "Configuring SSH for reverse tunnels..."
sudo sed -i 's/#GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config
sudo sed -i 's/GatewayPorts no/GatewayPorts yes/' /etc/ssh/sshd_config
grep -q "^GatewayPorts yes" /etc/ssh/sshd_config || echo "GatewayPorts yes" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart sshd

# Open firewall ports if firewalld is running
if systemctl is-active --quiet firewalld; then
    echo "Configuring firewall..."
    sudo firewall-cmd --permanent --add-port=6080/tcp
    sudo firewall-cmd --permanent --add-port=6688/tcp
    sudo firewall-cmd --reload
fi

echo ""
echo "=============================================="
echo "Setup complete!"
echo "=============================================="
echo ""
echo "Next steps:"
echo "1. Run ./ec2-reverse-proxy.sh to start the proxy (6688 -> 6080)"
echo "2. Ensure security group allows inbound on port 6688 from VPC Lattice"
echo "3. Submit the Deadline job to start the VNC container"
