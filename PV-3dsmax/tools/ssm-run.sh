#!/bin/bash
# Run a PowerShell script block on the SSM managed node and print its output.
# Usage: ssm-run.sh <script-file.ps1> [timeout-seconds] [node-id] [region]
set -euo pipefail

SCRIPT_FILE="$1"
TIMEOUT="${2:-600}"
NODE="${3:-mi-0d4a6f0f2f650d6be}"
REGION="${4:-us-west-2}"

# Package the script as a single JSON commands array entry.
PARAMS=$(python3 - "$SCRIPT_FILE" <<'PY'
import json, sys
body = open(sys.argv[1]).read()
print(json.dumps({"commands": [body]}))
PY
)

CMD_ID=$(aws ssm send-command \
  --instance-ids "$NODE" \
  --region "$REGION" \
  --document-name AWS-RunPowerShellScript \
  --parameters "$PARAMS" \
  --timeout-seconds "$TIMEOUT" \
  --query 'Command.CommandId' --output text)

echo "command: $CMD_ID" >&2

# Poll for completion.
for i in $(seq 1 $(( TIMEOUT / 10 + 6 ))); do
  STATUS=$(aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$NODE" \
    --region "$REGION" --query 'Status' --output text 2>/dev/null || echo Pending)
  case "$STATUS" in
    Success|Failed|Cancelled|TimedOut) break ;;
  esac
  sleep 10
done

echo "status: $STATUS" >&2
aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$NODE" \
  --region "$REGION" --query 'StandardOutputContent' --output text
ERR=$(aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$NODE" \
  --region "$REGION" --query 'StandardErrorContent' --output text)
if [ -n "$ERR" ] && [ "$ERR" != "None" ]; then
  echo "--- stderr ---" >&2
  echo "$ERR" >&2
fi
[ "$STATUS" = "Success" ]
