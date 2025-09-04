# Docker on Deadline Cloud (Q2 2025 Edition)

## Prerequisites

- **Deadline Farm, Fleet, Queue** - Set up and configured
- **Deadline CLI familiarity** - Commands like `deadline bundle submit .`
- **Amazon ECR repository** - Create one in AWS console (just click "create" and name it)
- **ECR commands familiarity** - `docker login`, `docker tag`, `docker push`
- **Docker image** - Built and pushed to ECR

## Setup Instructions

### 1. Configure Fleet

In the AWS console, navigate to **Deadline Cloud** → Select your **Farm** → **Fleet**

### 2. Fleet Configuration Script

In the fleet's **Configuration Script** tab, paste the following script:
- Set `min_worker_count` to **0**
- Set `max_worker_count` to **1** during debugging

```bash
# Install Docker
dnf install docker -y
sudo usermod -aG docker job-user
sudo systemctl start docker

# Optional: Only for debugging - give job-user sudo permission for docker
sudo usermod -aG wheel job-user
echo "job-user ALL=(ALL) NOPASSWD: /usr/bin/docker" | sudo EDITOR='tee -a' visudo
```

### 3. Fleet IAM Permissions

Navigate to the **Fleet** → Select the **IAM role** → Attach ECR permissions

**For debugging:** Use managed policy `AmazonEC2ContainerRegistryFullAccess`

**For production:** Use minimal IAM policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchGetImage",
                "ecr:GetDownloadUrlForLayer"
            ],
            "Resource": "*"
        }
    ]
}
```

**Permission Details:**
- `ecr:GetAuthorizationToken` - Required for ECR login authentication
- `ecr:BatchGetImage` - Required to pull image manifests
- `ecr:GetDownloadUrlForLayer` - Required to download image layers

**Note:** For restricted access, limit `Resource` for `BatchGetImage` and `GetDownloadUrlForLayer` to specific ECR repository ARNs:
```
"Resource": "arn:aws:ecr:region:account-id:repository/repository-name"
```

### 4. Queue IAM Permissions

Navigate to the **Queue** → Select the **IAM role** → Attach the same ECR permission set from Fleet role

### 5. Start Fleet Workers

Navigate to the **Fleet** → Set `min_worker_count` to **1**

**Monitor Setup:**
- Open **CloudWatch** → Navigate to log group: `/aws/deadline/farm-{uuid}/fleet-{uuid}`
- Wait for worker log to appear
- Verify Host Configuration script runs successfully

### 6. Test Basic Job Submission

Submit a Hello World job to verify the Fleet is working:

```bash
deadline bundle submit .
```

**Example:** [Simple Job Bundle](https://github.com/aws-deadline/deadline-cloud-samples/tree/mainline/job_bundles/simple_job)

### 7. Test Docker Integration

Submit a job that pulls and runs a Docker container.

**Add to job bundle template:**

```bash
# Login to ECR
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin {ECR_REPO_URL}

# Pull container
docker pull {ECR_REPO_URL}/{ECR_REPO_NAME}:{IMAGE_TAG}
```

**Example:**
```bash
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 013611968778.dkr.ecr.us-west-2.amazonaws.com
docker pull 013611968778.dkr.ecr.us-west-2.amazonaws.com/rendering:rocky-blender
```

### 8. Advanced Container Operations

Add to job template for complex rendering workflows:

```bash
# Simple container run
docker run \
    --volume '/sessions:/sessions' \
    --workdir '{{Session.WorkingDirectory}}' \
    -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    -e AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN \
    --rm \
    013611968778.dkr.ecr.us-west-2.amazonaws.com/hackathon-2025:rocky-blender \
    bash -c "pwd && ls && whoami"

# Detached container for long-running renders
CONTAINER_ID=$(docker run \
    -d \
    --volume '/sessions:/sessions' \
    --workdir '{{Session.WorkingDirectory}}' \
    -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    -e AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN \
    013611968778.dkr.ecr.us-west-2.amazonaws.com/hackathon-2025:rocky-blender \
    bash -c "blender --background --python /app/blender-mcp-bedrock/agents/addon.py")

echo $CONTAINER_ID
```

### 9. Execute Commands in Running Container

```bash
# Run additional commands for rendering
sudo docker exec $CONTAINER_ID python3 /path/to/render/script.py
```

### 10. Cleanup

Add to the end of job template:

```bash
# Cleanup any running containers
docker container prune -f
```

---

## Day-to-Day Workflow: Updating Images

### Prerequisites
- AWS permissions for ECR access

### Steps

1. **Login to ECR**
   ```bash
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 508726383309.dkr.ecr.us-east-1.amazonaws.com
   ```

2. **Build Docker Image**
   ```bash
   docker build -t my-image .
   ```

3. **Tag for ECR**
   ```bash
   docker tag my-image:latest <aws_account_id>.dkr.ecr.<region>.amazonaws.com/<repository-name>:latest
   ```

4. **Push to ECR**
   ```bash
   docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-repo:latest
   ```

5. **Automatic Updates**
   - If job template pulls the "latest" tag, next job submission will use updated container
   - **Performance Note:** Container layers enable fast delta downloads for cached workers

### Benefits
- **Layer Caching:** Only changed layers are downloaded
- **Fast Updates:** Workers with cached containers download deltas quickly
- **Version Control:** Use specific tags for reproducible builds