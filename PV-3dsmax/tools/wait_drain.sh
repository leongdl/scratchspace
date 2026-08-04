#!/bin/bash
FARM=farm-fd8e9a84d9c04142848c6ea56c9d7568
FLEET=fleet-25060df816a4493a88dc41840a25fbd6
# wait for workers to drain
for i in $(seq 1 20); do
  W=$(aws deadline list-workers --farm-id "$FARM" --fleet-id "$FLEET" --region us-west-2 \
      --query 'workers[?status!=`STOPPED` && status!=`NOT_RESPONDING`].[workerId,status]' --output text | tr '\t' ' ')
  V=$(aws deadline list-volumes --farm-id "$FARM" --fleet-id "$FLEET" --region us-west-2 \
      --query 'volumes[].[volumeId,state]' --output text | tr '\t' ' ')
  echo "$(date +%H:%M:%S) active-workers: ${W:-none} | volume: $V"
  if [ -z "$W" ]; then
    echo "Drained."
    break
  fi
  sleep 45
done
