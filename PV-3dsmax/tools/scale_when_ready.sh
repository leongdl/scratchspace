#!/bin/bash
# scale_when_ready.sh <min> <max>
FARM=farm-fd8e9a84d9c04142848c6ea56c9d7568
FLEET=fleet-25060df816a4493a88dc41840a25fbd6
for i in $(seq 1 30); do
  S=$(aws deadline get-fleet --farm-id "$FARM" --fleet-id "$FLEET" --region us-west-2 --query 'status' --output text)
  echo "$(date +%H:%M:%S) fleet: $S"
  if [ "$S" = "ACTIVE" ]; then
    aws deadline update-fleet --farm-id "$FARM" --fleet-id "$FLEET" --region us-west-2 \
      --min-worker-count "$1" --max-worker-count "$2" && echo "scaled to $1/$2" && exit 0
  fi
  sleep 20
done
exit 1
