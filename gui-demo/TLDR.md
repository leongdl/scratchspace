# TL;DR — New User Quick Start

Everything is already deployed. You just need to generate your key, register it, and submit.

## Prerequisites

- AWS CLI v2 with SSM plugin installed
- AWS credentials for account `257639634185` (us-west-2)
- Python 3 with `pip install deadline`

## Steps

```bash
# 1. Install the Deadline CLI
pip install deadline

# 2. Get AWS credentials and export them
#    (however your team handles this — Isengard, SSO, etc.)
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...

# 3. Generate your SSH tunnel key
cd gui-demo
bash generate_tunnel_key.sh

# 4. Register your public key on the EC2 bastion
PUB_KEY=$(cat job/vnc_tunnel_key.pub)
aws ssm send-command --instance-ids i-0227d51eeadb27c64 --region us-west-2 \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[\"echo '$PUB_KEY' >> /home/ssm-user/.ssh/authorized_keys\"]"

# 5. Submit the job
cd job
bash submit.sh

# 6. Start the SSM tunnel from your Mac
aws ssm start-session --target i-0227d51eeadb27c64 --region us-west-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["6080"],"localPortNumber":["6080"]}'

# 7. Open in browser
#    http://localhost:6080/vnc.html
#    Password: password

# 7b. Or connect with a native VNC client (TigerVNC, RealVNC, etc.)
#     Requires adding -R 5901:localhost:5901 to the reverse tunnel in template.yaml
#     Then start a second SSM tunnel:
aws ssm start-session --target i-0227d51eeadb27c64 --region us-west-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["5901"],"localPortNumber":["5901"]}'
#     Connect to: localhost:5901  Password: password
```

That's it. Steps 3-4 are one-time setup. After that, just repeat 5-7 each time you want a session.
