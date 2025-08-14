#!/usr/bin/env bash
set -euo pipefail

# Where am I?
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# -------------------------------
# Defaults (override via env/flags)
# -------------------------------
KEYCLOAK_VERSION="${KEYCLOAK_VERSION:-26.3}"
IMAGE_REPO="${IMAGE_REPO:-austinderbique/keycloak-trusted-device}"
IMAGE_NAME="${IMAGE_NAME:-${IMAGE_REPO}:${KEYCLOAK_VERSION}}"

REPO_URL="${REPO_URL:-https://github.com/wouterh-dev/keycloak-spi-trusted-device.git}"
REPO_DIR="${REPO_DIR:-${SCRIPT_DIR}/keycloak-spi-trusted-device}"
SPI_MODULE_REL_PATH="${SPI_MODULE_REL_PATH:-spi}"

PLATFORMS="${PLATFORMS:-linux/amd64}"      # e.g. "linux/amd64,linux/arm64"
PUSH="${PUSH:-false}"                      # true => push to registry
NO_CACHE="${NO_CACHE:-false}"

# File layout: put JAR next to Dockerfile (this dir)
PROVIDER_JAR_NAME="${PROVIDER_JAR_NAME:-keycloak-spi-trusted-device.jar}"
PROVIDER_JAR_PATH="${SCRIPT_DIR}/${PROVIDER_JAR_NAME}"
DOCKERFILE="${DOCKERFILE:-${SCRIPT_DIR}/Dockerfile}"
BUILD_CONTEXT="${BUILD_CONTEXT:-${SCRIPT_DIR}}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options (env vars also supported):
  -v, --version X.Y         Keycloak version (default: ${KEYCLOAK_VERSION})
  -i, --image-repo NAME     Image repo (default: ${IMAGE_REPO})
  -n, --image NAME[:TAG]    Full image name (default: ${IMAGE_NAME})

  -r, --repo URL            SPI repo URL (default: ${REPO_URL})
  -d, --repo-dir PATH       Local dir for SPI repo (default: ${REPO_DIR})
  -m, --module PATH         SPI module path in repo (default: ${SPI_MODULE_REL_PATH})

  -P, --platforms LIST      Buildx platforms (default: ${PLATFORMS})
      --push                Push image after build (default: ${PUSH})
      --no-cache            Build with no cache (default: ${NO_CACHE})

  -h, --help                Show this help

Examples:
  ./build.sh -v 26.3 --push
  PLATFORMS=linux/amd64,linux/arm64 KEYCLOAK_VERSION=26.1 PUSH=true ./build.sh
EOF
}

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version) KEYCLOAK_VERSION="$2"; shift 2 ;;
    -i|--image-repo) IMAGE_REPO="$2"; shift 2 ;;
    -n|--image) IMAGE_NAME="$2"; shift 2 ;;
    -r|--repo) REPO_URL="$2"; shift 2 ;;
    -d|--repo-dir) REPO_DIR="$2"; shift 2 ;;
    -m|--module) SPI_MODULE_REL_PATH="$2"; shift 2 ;;
    -P|--platforms) PLATFORMS="$2"; shift 2 ;;
    --push) PUSH="true"; shift ;;
    --no-cache) NO_CACHE="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# If IMAGE_NAME not explicitly tagged, sync to KEYCLOAK_VERSION
if [[ "${IMAGE_NAME}" != *:* ]]; then
  IMAGE_NAME="${IMAGE_REPO}:${KEYCLOAK_VERSION}"
fi

# Tool checks
command -v git >/dev/null 2>&1 || { echo "git not found" >&2; exit 1; }
command -v mvn >/dev/null 2>&1 || { echo "Maven not found" >&2; exit 1; }
docker buildx version >/dev/null 2>&1 || { echo "docker buildx not found" >&2; exit 1; }

# Clone/update SPI repo
if [[ -d "${REPO_DIR}" ]]; then
  echo "Updating SPI repo in ${REPO_DIR}..."
  ( cd "${REPO_DIR}" && git reset --hard && git clean -fd && git pull --ff-only ) || {
    echo "Pull failed; recloning..."
    rm -rf "${REPO_DIR}"
    git clone "${REPO_URL}" "${REPO_DIR}"
  }
else
  echo "Cloning SPI repo from ${REPO_URL} to ${REPO_DIR}..."
  git clone "${REPO_URL}" "${REPO_DIR}"
fi

# Build SPI JAR
BUILD_DIR="${REPO_DIR}/${SPI_MODULE_REL_PATH}"
echo "Building SPI in ${BUILD_DIR}..."
( cd "${BUILD_DIR}" && mvn -q -DskipTests package )
JAR_PATH="$(ls -1t "${BUILD_DIR}/target/"*.jar | head -n1)"
[[ -f "${JAR_PATH}" ]] || { echo "Error: JAR not found in ${BUILD_DIR}/target" >&2; exit 1; }

# Place JAR next to Dockerfile
cp -f "${JAR_PATH}" "${PROVIDER_JAR_PATH}"

# Buildx args
BUILD_ARGS=(
  --build-arg "KEYCLOAK_VERSION=${KEYCLOAK_VERSION}"
  --build-arg "PROVIDER_JAR=${PROVIDER_JAR_NAME}"
)
[[ "${NO_CACHE}" == "true" ]] && BUILD_ARGS+=(--no-cache)

# Build command (context = this dir)
CMD=(docker buildx build
  --platform "${PLATFORMS}"
  -t "${IMAGE_NAME}"
  "${BUILD_ARGS[@]}"
  -f "${DOCKERFILE}"
  "${BUILD_CONTEXT}"
)

# Push/Load behavior
if [[ "${PUSH}" == "true" ]]; then
  CMD+=(--push)
else
  # --load only for single-arch builds
  if [[ "${PLATFORMS}" != *","* ]]; then
    CMD+=(--load)
  else
    echo "Multi-arch without --push: image won't be loaded into local daemon."
  fi
fi

echo
echo "Building image:"
echo "  Keycloak version : ${KEYCLOAK_VERSION}"
echo "  Image            : ${IMAGE_NAME}"
echo "  Dockerfile       : ${DOCKERFILE}"
echo "  Context          : ${BUILD_CONTEXT}"
echo "  Platforms        : ${PLATFORMS}"
echo "  Push             : ${PUSH}"
echo "  No cache         : ${NO_CACHE}"
echo "  Provider JAR     : ${PROVIDER_JAR_PATH}"
echo

"${CMD[@]}"

echo
echo "✅ Build complete: ${IMAGE_NAME}"
[[ "${PUSH}" != "true" ]] && echo "Tip: set --push (or PUSH=true) to publish the image."

# Optional cleanup:
# rm -f "${PROVIDER_JAR_PATH}"

exit 0
