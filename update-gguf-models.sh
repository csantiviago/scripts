#!/bin/bash
set -euo pipefail

# Update GGUF models from Hugging Face, checking ETags to avoid unnecessary downloads
# Usage: ./update-gguf-models.sh [directory]
# If directory is not provided, uses current directory

GGUF_DIR="${1:-.}"
HF_API_BASE="https://huggingface.co/api/models"

# Color output (disabled if not a terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Extract repo and branch from model path
# Expected format: repo-name/branch/filename or repo-name/filename
parse_hf_path() {
    local filename="$1"
    local repo_name branch

    # Convert filename to repo name (e.g., llama-3-8b.Q4_K_M.gguf -> meta-llama/Meta-Llama-3-8B)
    # This is a basic mapping - customize based on your naming convention
    case "$filename" in
        *llama*|*Llama*)
            repo_name="meta-llama/Meta-Llama-3-8B"
            ;;
        *mistral*|*Mistral*)
            repo_name="mistralai/Mistral-7B-v0.1"
            ;;
        *gemma*|*Gemma*)
            repo_name="google/gemma-7b-it"
            ;;
        *phi*|*Phi*)
            repo_name="microsoft/phi-2"
            ;;
        *)
            # Default: assume filename without extension is the repo slug
            local base="${filename%.gguf}"
            repo_name="your-org/${base}"
            ;;
    esac

    # Default branch is main
    branch="main"

    echo "$repo_name $branch"
}

# Get ETag from Hugging Face
get_hf_etag() {
    local repo="$1"
    local filename="$2"
    local branch="$3"

    local url="${HF_API_BASE}/${repo}/tree/${branch}/${filename}"

    # Use curl to get ETag without downloading the file
    local etag
    etag=$(curl -sI "https://huggingface.co/${repo}/resolve/${branch}/${filename}" | \
           grep -i "^etag:" | \
           sed 's/^etag:[[:space:]]*//' | \
           tr -d '"\r\n')

    echo "$etag"
}

# Get local file ETag (based on size and mtime as a simple hash)
get_local_etag() {
    local filepath="$1"

    if [ ! -f "$filepath" ]; then
        echo ""
        return
    fi

    # Use file size and modification time as a simple identifier
    local size mtime
    size=$(stat -c%s "$filepath" 2>/dev/null || stat -f%z "$filepath" 2>/dev/null)
    mtime=$(stat -c%Y "$filepath" 2>/dev/null || stat -f%m "$filepath" 2>/dev/null)

    echo "${size}_${mtime}"
}

# Download model from Hugging Face
download_model() {
    local repo="$1"
    local filename="$2"
    local branch="$3"
    local dest="$4"

    local url="https://huggingface.co/${repo}/resolve/${branch}/${filename}"

    log_info "Downloading: $filename"
    log_info "From: $url"

    if curl -L -o "$dest.tmp" "$url"; then
        mv "$dest.tmp" "$dest"
        log_success "Downloaded: $filename"
        return 0
    else
        rm -f "$dest.tmp"
        log_error "Failed to download: $filename"
        return 1
    fi
}

# Check and update a single GGUF model
update_model() {
    local filename="$1"
    local filepath="${GGUF_DIR}/${filename}"

    log_info "Checking: $filename"

    # Parse Hugging Face path
    local hf_info
    hf_info=$(parse_hf_path "$filename")
    local repo branch
    read -r repo branch <<< "$hf_info"

    # Get remote ETag
    local remote_etag
    remote_etag=$(get_hf_etag "$repo" "$filename" "$branch")

    if [ -z "$remote_etag" ]; then
        log_warn "Could not get ETag for $filename (may not exist on Hugging Face)"
        return 1
    fi

    # Get local ETag
    local local_etag
    local_etag=$(get_local_etag "$filepath")

    # Compare ETags
    if [ -z "$local_etag" ]; then
        # File doesn't exist locally, download
        download_model "$repo" "$filename" "$branch" "$filepath"
    elif [ "$local_etag" != "$remote_etag" ]; then
        # ETags differ, model needs update
        log_info "Model changed, updating..."
        download_model "$repo" "$filename" "$branch" "$filepath"
    else
        # ETags match, skip
        log_success "Up-to-date: $filename"
    fi
}

# Main execution
main() {
    # Check if directory exists
    if [ ! -d "$GGUF_DIR" ]; then
        log_error "Directory not found: $GGUF_DIR"
        exit 1
    fi

    # Find all GGUF files
    local gguf_files
    gguf_files=$(find "$GGUF_DIR" -maxdepth 1 -name "*.gguf" -type f 2>/dev/null || true)

    if [ -z "$gguf_files" ]; then
        log_warn "No GGUF files found in: $GGUF_DIR"
        exit 0
    fi

    log_info "Scanning for GGUF models in: $(realpath "$GGUF_DIR")"
    echo ""

    local updated=0
    local skipped=0
    local failed=0

    while IFS= read -r filepath; do
        [ -z "$filepath" ] && continue

        local filename
        filename=$(basename "$filepath")

        if update_model "$filename"; then
            ((updated++)) || true
        else
            # Check if it was skipped (up-to-date) or failed
            if grep -q "Up-to-date" <<< "$(update_model "$filename" 2>&1)"; then
                ((skipped++)) || true
            else
                ((failed++)) || true
            fi
        fi
    done <<< "$gguf_files"

    echo ""
    log_info "Summary:"
    log_success "Updated: $updated"
    log_success "Skipped (up-to-date): $skipped"
    if [ "$failed" -gt 0 ]; then
        log_error "Failed: $failed"
    fi
}

main
