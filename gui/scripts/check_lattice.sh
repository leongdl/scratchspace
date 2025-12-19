#!/bin/bash
source scratchspace/gui/scripts/creds.sh
export AWS_DEFAULT_REGION=us-west-2

echo "=== VPC Lattice Resource Configuration ==="
aws vpc-lattice get-resource-configuration --resource-configuration-identifier rcfg-011bc61e9efbfbd1e > /tmp/lattice.txt 2>&1
cat /tmp/lattice.txt
