Here are some data:

My EC2 instance:
i-0dafdfc660885e366

My VPC:
vpc-0e8e227f1094b2f9a

My subnet:
subnet-0f145f86a08d5f76e

My security group:
sg-09d332611399f751a

Farm:
farm-fd8e9a84d9c04142848c6ea56c9d7568

Fleet:
fleet-8eebe8e8dc07489d97e6641aab3ad6fa

Queue:
queue-2eb8ef58ce5d48d1bbaf3e2f65ea2c38

VPC Lattice Resource Configuration:
arn:aws:vpc-lattice:us-west-2:224071664257:resourceconfiguration/rcfg-011bc61e9efbfbd1e
Endpoint: rcfg-011bc61e9efbfbd1e.resource-endpoints.deadline.us-west-2.amazonaws.com
Port: 22 (SSH - updated from 6688)

RAM Share:
arn:aws:ram:us-west-2:224071664257:resource-share/3cdab259-cc8d-40d5-86b9-fda0e62351d8
Name: deadline-vnc-share
Status: ACTIVE

## Key Fixes Applied

1. **VPC Lattice port**: Changed from 6688 to 22 so the worker can SSH to the EC2 proxy
2. **start.sh**: Added `wait` to keep container running, and backgrounded websockify
3. **Port check**: Changed from `nc -z` to `curl` for more reliable detection
4. **SSH user**: Using `ssm-user` instead of `ec2-user`
5. **SSH key**: Generated `vnc_tunnel_key` and added public key to EC2's authorized_keys