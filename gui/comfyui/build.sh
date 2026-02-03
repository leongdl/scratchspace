#!/bin/bash
# Build ComfyUI Docker images

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-}"

echo "=== Building ComfyUI Docker Images ==="

# Build base image
echo ""
echo "Building base image: comfyui-rocky:${IMAGE_TAG}"
docker build -t comfyui-rocky:${IMAGE_TAG} .

# Optionally build model-specific images
if [ "${BUILD_SDXL}" = "true" ]; then
    echo ""
    echo "Building SDXL image: comfyui-sdxl:${IMAGE_TAG}"
    docker build -f Dockerfile.sdxl -t comfyui-sdxl:${IMAGE_TAG} .
fi

if [ "${BUILD_FLUX}" = "true" ]; then
    echo ""
    echo "Building Flux image: comfyui-flux:${IMAGE_TAG}"
    docker build -f Dockerfile.flux -t comfyui-flux:${IMAGE_TAG} .
fi

# Push to registry if specified
if [ -n "${REGISTRY}" ]; then
    echo ""
    echo "Pushing to registry: ${REGISTRY}"
    
    docker tag comfyui-rocky:${IMAGE_TAG} ${REGISTRY}/comfyui-rocky:${IMAGE_TAG}
    docker push ${REGISTRY}/comfyui-rocky:${IMAGE_TAG}
    
    if [ "${BUILD_SDXL}" = "true" ]; then
        docker tag comfyui-sdxl:${IMAGE_TAG} ${REGISTRY}/comfyui-sdxl:${IMAGE_TAG}
        docker push ${REGISTRY}/comfyui-sdxl:${IMAGE_TAG}
    fi
    
    if [ "${BUILD_FLUX}" = "true" ]; then
        docker tag comfyui-flux:${IMAGE_TAG} ${REGISTRY}/comfyui-flux:${IMAGE_TAG}
        docker push ${REGISTRY}/comfyui-flux:${IMAGE_TAG}
    fi
fi

echo ""
echo "=== Build Complete ==="
echo ""
echo "Available images:"
docker images | grep comfyui
