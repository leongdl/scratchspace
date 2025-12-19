#!/bin/bash
source scratchspace/gui/scripts/creds.sh
export AWS_DEFAULT_REGION=us-west-2

echo "Updating VPC Lattice resource configuration to port 22..."
aws vpc-lattice update-resource-configuration \
  --resource-configuration-identifier rcfg-011bc61e9efbfbd1e \
  --port-ranges "22" > /tmp/update_lattice.txt 2>&1

cat /tmp/update_lattice.txt
