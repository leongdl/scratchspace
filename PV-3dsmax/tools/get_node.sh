#!/bin/bash
# Wait for the SSM job's session and extract the mi-* node ID from its log.
FARM=farm-fd8e9a84d9c04142848c6ea56c9d7568
QUEUE=queue-a928e259b15546df833ba209e8a50ca6
JOB="$1"
for i in $(seq 1 20); do
  SESSION=$(aws deadline list-sessions --farm-id "$FARM" --queue-id "$QUEUE" --job-id "$JOB" --region us-west-2 \
    --query 'sessions[0].sessionId' --output text 2>/dev/null)
  if [ "$SESSION" != "None" ] && [ -n "$SESSION" ]; then break; fi
  sleep 20
done
echo "session: $SESSION" >&2
for i in $(seq 1 20); do
  NODE=$(aws logs tail "/aws/deadline/$FARM/$QUEUE" --log-stream-names "$SESSION" --region us-west-2 --since 15m 2>/dev/null \
    | tr -d '\000' | grep -ao 'mi-[0-9a-f]*' | head -1)
  if [ -n "$NODE" ]; then echo "$NODE"; exit 0; fi
  sleep 20
done
echo "node not found" >&2
exit 1
