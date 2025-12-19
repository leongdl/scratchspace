#!/bin/bash
set -e

source scratchspace/gui/scripts/creds.sh

ACCOUNT_ID=224071664257
REGION=us-west-2
REPO_NAME=sqex2
IMAGE_TAG=rocky-vnc

# Login to ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Build the image
cd scratchspace/gui
docker build -t $REPO_NAME:$IMAGE_TAG -f Dockerfile.rocky .

# Tag for ECR
docker tag $REPO_NAME:$IMAGE_TAG $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:$IMAGE_TAG

# Push to ECR
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:$IMAGE_TAG

echo "Image pushed: $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:$IMAGE_TAG"
