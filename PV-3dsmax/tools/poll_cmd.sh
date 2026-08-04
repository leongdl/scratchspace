#!/bin/bash
# poll_cmd.sh <command-id> [max-minutes]
CMD="$1"
MAXMIN="${2:-15}"
NODE=mi-0d4a6f0f2f650d6be
for i in $(seq 1 $((MAXMIN * 2))); do
  STATUS=$(aws ssm get-command-invocation --command-id "$CMD" --instance-id "$NODE" --region us-west-2 --query 'Status' --output text 2>/dev/null)
  echo "$(date +%H:%M:%S) $STATUS"
  case "$STATUS" in Success|Failed|Cancelled|TimedOut) break;; esac
  sleep 30
done
aws ssm get-command-invocation --command-id "$CMD" --instance-id "$NODE" --region us-west-2 --output json > /tmp/inv.json
python3 -c "
import json
d = json.load(open('/tmp/inv.json'))
print('=== Status:', d['Status'], '===')
print(d['StandardOutputContent'][:3000])
err = d['StandardErrorContent']
if err.strip(): print('--- stderr ---'); print(err[:1500])
"
