#!/bin/bash
source scratchspace/gui/scripts/creds.sh

echo "=== RAM Resource Shares ==="
aws ram get-resource-shares --resource-owner SELF --region us-west-2

echo ""
echo "=== RAM Resources for VPC Lattice config ==="
aws ram list-resources --resource-owner SELF --region us-west-2 --resource-arns arn:aws:vpc-lattice:us-west-2:224071664257:resourceconfiguration/rcfg-011bc61e9efbfbd1e

echo ""
echo "=== Deadline Fleet VPC Resource Endpoints ==="
aws deadline get-fleet --farm-id farm-fd8e9a84d9c04142848c6ea56c9d7568 --fleet-id fleet-8eebe8e8dc07489d97e6641aab3ad6fa --region us-west-2 --query 'configuration.serviceManagedEc2'
