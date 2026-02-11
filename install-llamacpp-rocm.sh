#!/usr/bin/env bash
set -euo pipefail

# Install llama.cpp ROCm binaries for AMD RX 7900 XTX
# Source: https://github.com/lemonade-sdk/llamacpp-rocm

LLAMA_DIR="${HOME}/llm/llama.cpp"
OWNER="lemonade-sdk"
REPO="llamacpp-rocm"
FORCE="${FORCE:-0}"

# Safety: Ensure we're on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo "Error: This script is for Linux only. ROCm requires Linux."
    exit 1
fi

# Safety: Check if required commands are available
for cmd in curl unzip jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' not found. Please install it first."
        exit 1
    fi
done

# Safety: Check if target directory is writable
if [ ! -w "$LLAMA_DIR" ] && [ ! -w "$(dirname "$LLAMA_DIR")" ]; then
    echo "Error: No write permission for target directory: $LLAMA_DIR"
    exit 1
fi

# Safety: Check if ROCm/HIP is likely installed
if ! command -v rocminfo &> /dev/null && ! ls /opt/rocm/hip/lib/*.so 2>/dev/null; then
    echo "Warning: ROCm/HIP appears to be missing. This script requires ROCm runtime."
    echo "Install from: https://docs.amd.com/en/latest/rocm-install/Installing-RoCM.html"
fi

echo "Installing llama.cpp ROCm for $USER..."
echo "Target: $LLAMA_DIR"

# Create target directory if it doesn't exist
mkdir -p "$LLAMA_DIR"

# Fetch latest release info
echo "Fetching latest release from $OWNER/$REPO..."
LATEST_URL="https://api.github.com/repos/$OWNER/$REPO/releases/latest"

# Parse JSON to get tag name and assets
ASSETS_JSON=$(curl -s "$LATEST_URL")
TAG=$(echo "$ASSETS_JSON" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$TAG" ]; then
    echo "Error: Could not fetch latest release tag"
    exit 1
fi

echo "Latest release: $TAG"

# Find asset URL for RX 7900 XTX (gfx110X = RDNA 3, RX 7000 series)
# Assets are named like: llama-{tag}-ubuntu-rocm-gfx110X-x64.zip
ASSET_URL=$(echo "$ASSETS_JSON" | jq -r '.assets[] | select(.name | contains("gfx110X") and contains("ubuntu")) | .browser_download_url' 2>/dev/null || \
    echo "$ASSETS_JSON" | grep '"browser_download_url": "[^"]*ubuntu[^"]*gfx110X[^"]*"' | sed 's/"browser_download_url": "\(.*\)"/\1/')

if [ -z "$ASSET_URL" ]; then
    echo "Error: Could not find asset URL for gfx110X Ubuntu"
    echo "Available assets:"
    echo "$ASSETS_JSON" | jq -r '.assets[].name' 2>/dev/null || \
        echo "$ASSETS_JSON" | grep '"name":' | sed 's/.*"name": "\(.*\)"/  - \1/'
    exit 1
fi

echo "Downloading from: $ASSET_URL"
cd "$LLAMA_DIR"

# Download the zip file
DOWNLOAD_FILE="llama-rocm.zip"
curl -sSL -o "$DOWNLOAD_FILE" "$ASSET_URL"

# Check if download succeeded
if [ ! -f "$DOWNLOAD_FILE" ]; then
    echo "Error: Download failed. File not created."
    exit 1
fi

# Get file size for sanity check (Linux only, we verify OSTYPE earlier)
FILE_SIZE=$(stat -c%s "$DOWNLOAD_FILE")
if [ "$FILE_SIZE" -lt 100000 ]; then
    echo "Error: Download file is suspiciously small ($FILE_SIZE bytes). Network issue?"
    exit 1
fi

# Unzip and clean up
echo "Extracting..."
unzip -q -o "$DOWNLOAD_FILE"

# Clean up zip
rm "$DOWNLOAD_FILE"

# Verify critical files exist
if [ ! -f "llama-cli" ]; then
    echo "Error: Extraction failed - llama-cli not found"
    exit 1
fi

echo "Installation complete! llama.cpp is in: $LLAMA_DIR"
