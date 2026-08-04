#!/bin/bash
FARM=farm-fd8e9a84d9c04142848c6ea56c9d7568
QUEUE=queue-a928e259b15546df833ba209e8a50ca6
JOB=job-52fcb743716e4888aaed090f96fe0e49
for i in $(seq 1 15); do
  S=$(aws deadline get-job --farm-id "$FARM" --queue-id "$QUEUE" --job-id "$JOB" --region us-west-2 \
      --query '[lifecycleStatus,taskRunStatus]' --output text | tr '\t' ' ')
  echo "$(date +%H:%M:%S) job: $S"
  if echo "$S" | grep -qE 'RUNNING'; then break; fi
  if echo "$S" | grep -qE 'FAILED|CANCELED|SUCCEEDED'; then break; fi
  sleep 30
done
# find session
aws deadline list-sessions --farm-id "$FARM" --queue-id "$QUEUE" --job-id "$JOB" --region us-west-2 \
  --query 'sessions[].[sessionId,lifecycleStatus]' --output text
