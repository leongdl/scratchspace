#!/bin/bash
# Generate the SSH key pair used for the reverse tunnel between
# Deadline SMF workers and the EC2 bastion.
#
# - Private key: job/vnc_tunnel_key  (attached to the Deadline job)
# - Public key:  job/vnc_tunnel_key.pub (add to EC2 authorized_keys)

set -e

KEY_PATH="job/vnc_tunnel_key"

if [ -f "$KEY_PATH" ]; then
  echo "Key already exists at $KEY_PATH — skipping."
  echo "Delete it first if you want to regenerate."
  exit 0
fi

ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "deadline-vnc-tunnel"

echo ""
echo "Done. Files created:"
echo "  Private key: $KEY_PATH"
echo "  Public key:  ${KEY_PATH}.pub"
echo ""
echo "Next: add the public key to the EC2 bastion:"
echo "  cat ${KEY_PATH}.pub >> /home/ssm-user/.ssh/authorized_keys"
