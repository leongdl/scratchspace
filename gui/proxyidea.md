I have an idea to use deadline cloud's Service Managed Fleet worker as a remote desktop.

1. We already built a GUI docker container in Dockerfile.rocky. I have tested it and I can access the VNC desktop. Read rockyhelp.md for the right ports in case I get them mixed up.

2. I want to achieve the following setup.

```
mac <-> ec2 instance <-> VPC Lattice to expose the ec2 instance on port 6688 <-> Deadline SMF instance running rocky VNC container with --host. 
```

3. My workflow.
  a. My mac will start the ssm session to port forward 6080 to the EC2 instance.
  b. My ec2 instance will listen on port 6688 and forward all traffic to 6080
  c. I want to configure the subnet and security group to allow a VPC Lattice connection to port 6688 of the ec2.
  d. I want to submit a deadline cloud job (example under job), where a step downloads the container. Then start the container with the --host network. Then do a reverse ssh connection to forward all traffic from the VPC lattice endpoint to port 6080 of the docker container. 


End goal - I want to be able to visit localhost:6080 from my mac to access the docker container. I want the traffic to be forwarded from mac to the intermedia ec2 to deadline cloud.

Extra information:

From my mac, I can create a SSM tunnel to the proxy instance:
```
#!/bin/bash
INSTANCE_ID=i-0dafdfc660885e366
INSTANCE_REGION=us-west-2
aws ssm start-session --target $INSTANCE_ID --region $INSTANCE_REGION \
                       --document-name AWS-StartPortForwardingSession \
                       --parameters '{"portNumber":["6080"],"localPortNumber":["6080"]}'
```

Question
1. Can you create a the script on the ec2 instance that can listen and forward traffic from 6688 to 6080 to act as a reverse proxy?
2. Can you create a job bundle that starts the container and connects to the vpc lattice endpoint.
3. Can you provide me a script to setup the tunnel on my mac to the ec2.
4. Can you give me steps to setup VPC lattice correctly, also check if my security groups are correct.

Context:
Write the scripts under gui/scripts and label them clearly. 
Write the job template and update the one in gui/job.