#!/bin/bash
# Quick-run wrapper with defaults for leongdl's environment.
# Sources venv and sets farm/queue/ECR, then calls submit.sh.
#
# Usage:
#   ./run.sh                    # 120 min session
#   ./run.sh 240                # 4 hours
#   ./run.sh 120 --show         # show activation code

set -e

source ~/venv/bin/activate

export FARM_ID="${FARM_ID:-farm-fd8e9a84d9c04142848c6ea56c9d7568}"
export QUEUE_ID="${QUEUE_ID:-queue-2eb8ef58ce5d48d1bbaf3e2f65ea2c38}"
export ECR_REGISTRY="${ECR_REGISTRY:-224071664257.dkr.ecr.us-west-2.amazonaws.com}"
export DOCKER_REPO="${DOCKER_REPO:-sqex2}"
export DOCKER_TAG="${DOCKER_TAG:-wans2v}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "${SCRIPT_DIR}/submit.sh" "$@"
