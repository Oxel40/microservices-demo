#!/usr/bin/env bash
# Builds every microservices-demo service for linux/amd64+arm64 and pushes to ghcr.io.
# Run from anywhere inside this checkout, e.g.:
#   GHCR_USER=oxel40 ./build-boutique-images.sh v0.10.5
#
# Requires: docker buildx plugin, and `docker login ghcr.io` already done
# (or GHCR_TOKEN set: echo $GHCR_TOKEN | docker login ghcr.io -u $GHCR_USER --password-stdin).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAG="${1:?usage: $0 <tag>}"
GHCR_USER="${GHCR_USER:?set GHCR_USER=<your-github-username>}"
REGISTRY="ghcr.io/${GHCR_USER}/microservices-demo"
PLATFORMS="linux/amd64,linux/arm64"
BUILDER_NAME="boutique-multiarch"

# service -> build context (relative to SRC_DIR), per src/../skaffold.yaml
declare -A SERVICES=(
  [emailservice]=src/emailservice
  [productcatalogservice]=src/productcatalogservice
  [recommendationservice]=src/recommendationservice
  [shoppingassistantservice]=src/shoppingassistantservice
  [shippingservice]=src/shippingservice
  [checkoutservice]=src/checkoutservice
  [paymentservice]=src/paymentservice
  [currencyservice]=src/currencyservice
  [cartservice]=src/cartservice/src
  [frontend]=src/frontend
  [adservice]=src/adservice
  [loadgenerator]=src/loadgenerator
)

if ! docker buildx version >/dev/null 2>&1; then
  echo "docker buildx plugin not installed. On Arch: sudo pacman -S docker-buildx" >&2
  exit 1
fi

# emailservice/loadgenerator/recommendationservice/shoppingassistantservice run `apk add`
# in the final (target-arch) stage, so real arm64 execution is needed at build time, not
# just cross-compilation. Register binfmt handlers once so buildx can emulate them.
if ! docker run --rm --privileged tonistiigi/binfmt --help >/dev/null 2>&1; then
  echo "docker not available or no network access to pull tonistiigi/binfmt" >&2
  exit 1
fi
docker run --rm --privileged tonistiigi/binfmt --install arm64

# The default "docker" buildx driver can't emit multi-platform images; a
# docker-container driver spins up a dedicated buildkit instance that can.
if ! docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
  docker buildx create --name "$BUILDER_NAME" --driver docker-container --use
else
  docker buildx use "$BUILDER_NAME"
fi

for svc in "${!SERVICES[@]}"; do
  ctx="${SRC_DIR}/${SERVICES[$svc]}"
  echo "=== building ${svc} (${ctx}) ==="
  docker buildx build \
    --platform "$PLATFORMS" \
    -t "${REGISTRY}/${svc}:${TAG}" \
    --push \
    "$ctx"
done

echo
echo "Done. Images pushed:"
for svc in "${!SERVICES[@]}"; do
  echo "  ${REGISTRY}/${svc}:${TAG}"
done
