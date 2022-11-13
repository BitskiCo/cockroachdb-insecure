#!/bin/sh

set -ex

SRCDIR=$(realpath "$(dirname "${0}")")

: ${VERSION:=$(
    docker pull -q cockroachdb/cockroach:latest >/dev/null
    docker image inspect \
        --format='{{ (index .Config.Labels "version") }}' \
        cockroachdb/cockroach:latest
)}

: ${TAG:="v${VERSION}"}
: ${BASE_IMAGE:="ghcr.io/bitskico/cockroach"}
: ${IMAGE:="ghcr.io/bitskico/cockroachdb-insecure"}
: ${UPSTREAM_IMAGE:="cockroachdb/cockroach"}

: ${WORKDIR:=$(mktemp -d --suffix=.cockroach-insecure || echo "${SRCDIR}/build")}

# Build ARM64 images

mkdir -p "$WORKDIR"
cd "$WORKDIR"

git clone --branch="$TAG" --depth=1 --no-recurse-submodules --no-tags \
    https://github.com/cockroachdb/cockroach

cd cockroach

./build/builder.sh pull
./build/builder.sh mkrelease arm64-linux-gnu

cp cockroach-linux-*-gnu-aarch64 build/deploy/cockroach
cp "$GOPATH/docker/native/aarch64-unknown-linux-gnu/geos/lib/libgeos.so" \
    "$GOPATH/docker/native/aarch64-unknown-linux-gnu/geos/lib/libgeos_c.so" \
    build/deploy/
cp -r licenses build/deploy/

BUILDER=$(docker buildx create --platform=linux/amd64,linux/arm64)

docker buildx build --builder="$BUILDER" --push \
    --platform=linux/arm64 \
    -t "${BASE_IMAGE}:${TAG}-arm64" build/deploy

cd "$SRCDIR"
rm -rf "$WORKDIR"

docker buildx build --builder="$BUILDER" --push \
    --platform linux/arm64 \
    --build-arg BASE_IMAGE="${BASE_IMAGE}:${TAG}-arm64" \
    --tag "${IMAGE}:${TAG}-arm64" .

docker buildx rm "$BUILDER"

# Build AMD64 images

docker pull "${UPSTREAM_IMAGE}:${TAG}"
docker tag "${UPSTREAM_IMAGE}:${TAG}" "${BASE_IMAGE}:${TAG}-amd64"
docker push "${BASE_IMAGE}:${TAG}-amd64"

docker buildx build --push \
    --build-arg BASE_IMAGE="${BASE_IMAGE}:${TAG}-amd64" \
    --tag "${IMAGE}:${TAG}-amd64" .

# Create multi-arch manifest

docker manifest rm "${BASE_IMAGE}:${TAG}" || true
docker manifest create "${BASE_IMAGE}:${TAG}" \
    --amend "${BASE_IMAGE}:${TAG}-amd64" \
    --amend "${BASE_IMAGE}:${TAG}-arm64"
docker manifest push "${BASE_IMAGE}:${TAG}"

docker manifest rm "${IMAGE}:${TAG}" || true
docker manifest create "${IMAGE}:${TAG}" \
    --amend "${IMAGE}:${TAG}-amd64" \
    --amend "${IMAGE}:${TAG}-arm64"
docker manifest push "${IMAGE}:${TAG}"
