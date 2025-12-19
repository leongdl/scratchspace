#!/bin/bash
source scratchspace/gui/scripts/creds.sh

export AWS_DEFAULT_REGION=us-west-2

FARM_ID=farm-fd8e9a84d9c04142848c6ea56c9d7568
QUEUE_ID=queue-2eb8ef58ce5d48d1bbaf3e2f65ea2c38
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

cd scratchspace/gui/job

deadline bundle submit . \
  --farm-id $FARM_ID \
  --queue-id $QUEUE_ID \
  --name "VNC-Desktop-$TIMESTAMP" \
  --yes > /tmp/submit_output.txt 2>&1

cat /tmp/submit_output.txt
