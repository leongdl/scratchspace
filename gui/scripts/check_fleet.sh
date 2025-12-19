#!/bin/bash
source scratchspace/gui/scripts/creds.sh

aws deadline get-fleet --farm-id farm-fd8e9a84d9c04142848c6ea56c9d7568 --fleet-id fleet-8eebe8e8dc07489d97e6641aab3ad6fa --region us-west-2 --query 'configuration.serviceManagedEc2.vpcConfiguration' --output json > /tmp/fleet_vpc.json

cat /tmp/fleet_vpc.json
