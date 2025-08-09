#!/usr/bin/env bash
set -euo pipefail

# Build and push per-model, per-GPU images to Harbor

HARBOR_ENDPOINT=harbor-core.ai.svc.cluster.local
IMAGE_TAG=${IMAGE_TAG:-v1}
GPU=${GPU:-3090}

REG_PREFIX="$HARBOR_ENDPOINT/ai"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Building baseline image for GPU=$GPU, tag=$IMAGE_TAG"
docker build \
  -f "$ROOT_DIR/kubernetes/docker/Dockerfile.ollama-base" \
  -t "$REG_PREFIX/ollama-base-$GPU:$IMAGE_TAG" \
  "$ROOT_DIR"

docker push "$REG_PREFIX/ollama-base-$GPU:$IMAGE_TAG"

MODELS=("gpt-oss" "gemma3" "qwen3")

for MODEL in "${MODELS[@]}"; do
  echo "==> Building model=$MODEL for GPU=$GPU"
  docker build \
    -f "$ROOT_DIR/kubernetes/docker/Dockerfile.model" \
    --build-arg MODEL="$MODEL" \
    --build-arg GPU_ARCH="$GPU" \
    -t "$REG_PREFIX/ollama-$MODEL-$GPU:$IMAGE_TAG" \
    "$ROOT_DIR"

  docker push "$REG_PREFIX/ollama-$MODEL-$GPU:$IMAGE_TAG"
done

echo "All images pushed to $REG_PREFIX with tag $IMAGE_TAG"

