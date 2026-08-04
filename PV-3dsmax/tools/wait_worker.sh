#!/bin/bash
FARM=farm-fd8e9a84d9c04142848c6ea56c9d7568
FLEET=fleet-25060df816a4493a88dc41840a25fbd6
for i in $(seq 1 20); do
  W=$(aws deadline list-workers --farm-id "$FARM" --fleet-id "$FLEET" --region us-west-2 \
      --query 'workers[].[workerId,status]' --output text | tr '\t' ' ')
  echo "$(date +%H:%M:%S) workers: ${W:-none}"
  if echo "$W" | grep -qE 'STARTED|IDLE|RUNNING'; then
    echo "Worker ready."
    exit 0
  fi
  sleep 60
done
echo "Timed out waiting for worker."
exit 1
