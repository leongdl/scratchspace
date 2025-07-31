#!/bin/bash

# SSH tunnel script to connect to Thinkbox development license server
# This creates a secure tunnel through the bastion host

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define paths relative to the script location
CONFIG_FILE="$SCRIPT_DIR/config"
SSH_KEY="$SCRIPT_DIR/leongdl"

# Check if required files exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: SSH config file not found at $CONFIG_FILE"
    exit 1
fi

if [ ! -f "$SSH_KEY" ]; then
    echo "Error: SSH private key not found at $SSH_KEY"
    exit 1
fi

# Set proper permissions on the SSH key
chmod 600 "$SSH_KEY"

echo "Connecting to Thinkbox development license server..."
echo "Config: $CONFIG_FILE"
echo "Key: $SSH_KEY"
echo "Press Ctrl+C to disconnect"

# Execute the SSH tunnel command
ssh -v -N -F "$CONFIG_FILE" -i "$SSH_KEY" bastion-external@bastion.dev-lic.thinkboxsoftware.com