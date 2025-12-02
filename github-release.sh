#!/usr/bin/env bash
set -euo pipefail

# github-release.sh
# Initialize (if needed), push, tag, and create a GitHub release for a specified code directory.
# - Stages/commits BEFORE attempting to create the GitHub repo (so `gh repo create` works nicely).
# - Uses GITHUB_TOKEN or ~/.git-credentials (if present) to avoid interactive username/password prompts.

OWNER=""
REPO_NAME=""
REPO_FULL=""
CODE_DIR=""
BRANCH="main"
REMOTE_NAME="origin"
VISIBILITY="private"
VERSION_TAG=""
COMMIT_MSG=""
ATTACH_ZIP="false"
FORCE_PUSH="false"

die() { echo "ERROR: $*" >&2; exit 1; }
info(){ echo "[INFO] $*"; }
warn(){ echo "[WARN] $*"; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") -d <code_dir> [-r <owner/repo> | -o <owner> -n <repo_name>] [options]
  -d, --dir DIR              Path to the code directory (required)
  -r, --repo OWNER/NAME      Full repo name, e.g. "user/my-repo"
  -o, --owner OWNER          GitHub owner (user or org)
  -n, --name NAME            GitHub repository name
  -b, --branch BRANCH        Default branch name (default: main)
      --remote REMOTE        Git remote name (default: origin)
      --public               Create public repo (default: private)
      --private              Create private repo (default)
  -v, --version TAG          Release tag (default: vYYYYMMDD-HHMMSS)
  -m, --message MSG          Commit message / release notes (default: "Release <TAG>")
      --zip                  Zip the directory and attach to GitHub release
      --force-push           Allow force push with lease if needed
  -h, --help                 Show help
EOF
}

# Parse args
[[ $# -gt 0 ]] || { usage; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir) CODE_DIR="${2:-}"; shift 2;;
    -r|--repo) REPO_FULL="${2:-}"; shift 2;;
    -o|--owner) OWNER="${2:-}"; shift 2;;
    -n|--name) REPO_NAME="${2:-}"; shift 2;;
    -b|--branch) BRANCH="${2:-}"; shift 2;;
    --remote) REMOTE_NAME="${2:-}"; shift 2;;
    --public) VISIBILITY="public"; shift;;
    --private) VISIBILITY="private"; shift;;
    -v|--version) VERSION_TAG="${2:-}"; shift 2;;
    -m|--message) COMMIT_MSG="${2:-}"; shift 2;;
    --zip) ATTACH_ZIP="true"; shift;;
    --force-push) FORCE_PUSH="true"; shift;;
    -h|--help) usage; exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

[[ -n "$CODE_DIR" ]] || die "Missing --dir"
[[ -d "$CODE_DIR" ]] || die "Directory not found: $CODE_DIR"

# Repo naming
if [[ -n "$REPO_FULL" ]]; then
  [[ "$REPO_FULL" == */* ]] || die "--repo must be OWNER/NAME"
  OWNER="${REPO_FULL%/*}"
  REPO_NAME="${REPO_FULL#*/}"
elif [[ -n "$OWNER" && -n "$REPO_NAME" ]]; then
  REPO_FULL="${OWNER}/${REPO_NAME}"
else
  die "Provide either --repo OWNER/NAME or both --owner and --name"
fi

# Defaults
[[ -n "$VERSION_TAG" ]] || VERSION_TAG="v$(date +%Y%m%d-%H%M%S)"
[[ -n "$COMMIT_MSG" ]] || COMMIT_MSG="Release ${VERSION_TAG}"

has_cmd git || die "git not found"

CODE_DIR="$(cd "$CODE_DIR" && pwd)"
cd "$CODE_DIR"

# Initialize repo if needed
if [[ ! -d ".git" ]]; then
  info "Initializing git repository in $CODE_DIR"
  git init
  git checkout -B "$BRANCH"
  # Minimal files
  if [[ ! -f ".gitignore" ]]; then
    cat > .gitignore <<'GITIGNORE'
.DS_Store
Thumbs.db
*.log
node_modules/
dist/
__pycache__/
*.pyc
vendor/
*.swp
*.swo
.cache/
GITIGNORE
    info "Created .gitignore"
  fi
  if [[ ! -f "README.md" ]]; then
    cat > README.md <<EOF2
# ${REPO_NAME}

Initialized by github-release.sh on $(date -Iseconds).
Default branch: \`${BRANCH}\`
Visibility: \`${VISIBILITY}\`
EOF2
    info "Created README.md"
  fi
fi

# Ensure branch
git checkout -B "$BRANCH"

# Stage & commit BEFORE remote/repo creation
git add -A
if ! git diff --cached --quiet; then
  git commit -m "$COMMIT_MSG"
else
  info "No staged changes to commit."
fi

# Remote URLs
REMOTE_URL_SSH="git@github.com:${REPO_FULL}.git"
REMOTE_URL_HTTPS="https://github.com/${REPO_FULL}.git"
REMOTE_URL_HTTPS_TOKEN=""

# Prefer GITHUB_TOKEN, fall back to ~/.git-credentials if present
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  GIT_USER="${GITHUB_USER:-x-access-token}"
  REMOTE_URL_HTTPS_TOKEN="https://${GIT_USER}:${GITHUB_TOKEN}@github.com/${REPO_FULL}.git"
elif [[ -f "$HOME/.git-credentials" ]]; then
  # Look for a line like: https://user:token@github.com (no extra path)
  CRED_LINE_RAW="$(grep -E '^https://[^:]+:[^@]+@github\.com/?$' "$HOME/.git-credentials" | head -n1 || true)"
  if [[ -n "$CRED_LINE_RAW" ]]; then
    # Normalize: drop trailing slash if any
    CRED_BASE="${CRED_LINE_RAW%/}"
    REMOTE_URL_HTTPS_TOKEN="${CRED_BASE}/${REPO_FULL}.git"
    info "Using credentials from ~/.git-credentials for GitHub HTTPS."
  fi
fi

# Remote setup / upgrade
if git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
  EXISTING_URL="$(git remote get-url "$REMOTE_NAME")"
  info "Remote '$REMOTE_NAME' already set to $EXISTING_URL"
  # If we have a token/credential-based URL, always normalize/override the remote
  if [[ -n "$REMOTE_URL_HTTPS_TOKEN" ]]; then
    git remote set-url "$REMOTE_NAME" "$REMOTE_URL_HTTPS_TOKEN"
    info "Updated remote '$REMOTE_NAME' to token-authenticated HTTPS URL."
  fi
else
  # No remote yet: decide what to use
  if [[ -n "$REMOTE_URL_HTTPS_TOKEN" ]]; then
    git remote add "$REMOTE_NAME" "$REMOTE_URL_HTTPS_TOKEN"
    info "Added remote '$REMOTE_NAME' -> $REMOTE_URL_HTTPS_TOKEN (HTTPS with token/credentials)"
  elif [[ -f "$HOME/.ssh/id_rsa" || -f "$HOME/.ssh/id_ed25519" ]]; then
    git remote add "$REMOTE_NAME" "$REMOTE_URL_SSH"
    info "Added remote '$REMOTE_NAME' -> $REMOTE_URL_SSH (SSH)"
  else
    git remote add "$REMOTE_NAME" "$REMOTE_URL_HTTPS"
    info "Added remote '$REMOTE_NAME' -> $REMOTE_URL_HTTPS (plain HTTPS – may prompt if repo is private)"
  fi
fi

create_repo_if_needed() {
  # Prefer gh only if authenticated; otherwise fall back to REST if GITHUB_TOKEN is set
  if has_cmd gh && gh auth status >/dev/null 2>&1; then
    if gh repo view "$REPO_FULL" >/dev/null 2>&1; then
      info "Remote GitHub repo exists: $REPO_FULL"
      return 0
    fi
    info "Creating GitHub repo with gh: $REPO_FULL ($VISIBILITY)"
    gh repo create "$REPO_FULL" --"$VISIBILITY" --source "." --disable-issues --disable-wiki || \
      die "Failed to create repo via gh"
    return 0
  fi

  [[ -n "${GITHUB_TOKEN:-}" ]] || die "GITHUB_TOKEN not set; cannot create repo without authenticated gh"

  local API_URL="https://api.github.com"
  # First, check if the repo already exists
  local CHECK
  CHECK=$(curl -sS -H "Authorization: Bearer $GITHUB_TOKEN" \
                 -H "Accept: application/vnd.github+json" \
                 "$API_URL/repos/${REPO_FULL}" || true)
  if echo "$CHECK" | grep -q '"full_name"'; then
    info "Remote GitHub repo already exists: $REPO_FULL"
    return 0
  fi

  info "Creating GitHub repo via REST API"
  local RESP
  RESP=$(curl -sS -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
               -H "Accept: application/vnd.github+json" \
               "$API_URL/user/repos" \
               -d "{\"name\":\"$REPO_NAME\",\"private\":$( [[ \"$VISIBILITY\" == \"private\" ]] && echo true || echo false )}")
  if echo "$RESP" | grep -q '"full_name"'; then
    info "Created GitHub repo: $REPO_FULL"
    return 0
  fi

  echo "$RESP" >&2
  die "Failed to create repo via API"
}

# Try to reach remote; if not, create it
if ! git ls-remote "$REMOTE_NAME" &>/dev/null; then
  info "Remote repository not reachable or empty; will attempt to ensure it exists on GitHub."
  create_repo_if_needed
fi

# Determine if first push
FIRST_PUSH="false"
if ! git ls-remote --heads "$REMOTE_NAME" "$BRANCH" >/dev/null 2>&1; then
  info "Remote branch '$BRANCH' not found. Performing first push workflow."
  FIRST_PUSH="true"
fi

if [[ "$FIRST_PUSH" == "true" ]]; then
  # Integrate any existing remote commits (README/license)
  if git ls-remote "$REMOTE_NAME" | grep -q .; then
    info "Remote has content. Pulling with rebase and allowing unrelated histories."
    git fetch "$REMOTE_NAME"
    git pull --rebase --allow-unrelated-histories "$REMOTE_NAME" "$BRANCH" || true
  fi
  if [[ "$FORCE_PUSH" == "true" ]]; then
    git push --force-with-lease -u "$REMOTE_NAME" "$BRANCH"
  else
    git push -u "$REMOTE_NAME" "$BRANCH"
  fi
else
  info "Fetching and rebasing onto remote before push..."
  git fetch "$REMOTE_NAME" "$BRANCH" || true
  if git rev-parse --verify "refs/remotes/$REMOTE_NAME/$BRANCH" >/dev/null 2>&1; then
    git rebase "$REMOTE_NAME/$BRANCH" || true
  fi
  if [[ "$FORCE_PUSH" == "true" ]]; then
    git push --force-with-lease "$REMOTE_NAME" "$BRANCH"
  else
    git push "$REMOTE_NAME" "$BRANCH"
  fi
fi

# Tag & push tag
if ! git rev-parse "$VERSION_TAG" >/dev/null 2>&1; then
  git tag -a "$VERSION_TAG" -m "$COMMIT_MSG"
else
  warn "Tag '$VERSION_TAG' already exists locally."
fi
if ! git ls-remote --tags "$REMOTE_NAME" | grep -q "refs/tags/${VERSION_TAG}$"; then
  git push "$REMOTE_NAME" "$VERSION_TAG" || warn "Failed to push tag '$VERSION_TAG'"
else
  warn "Tag '$VERSION_TAG' already exists on remote."
fi

# Optional asset zip & release
ZIPFILE=""
if [[ "$ATTACH_ZIP" == "true" ]]; then
  has_cmd zip || die "zip not found but --zip was requested"
  ZIPFILE="/tmp/${REPO_NAME}-${VERSION_TAG}.zip"
  info "Creating zip artifact: $ZIPFILE"
  (shopt -s dotglob nullglob; cd "$CODE_DIR" && zip -r "$ZIPFILE" . >/dev/null)
fi

create_release() {
  local notes="$COMMIT_MSG"
  if has_cmd gh && gh auth status >/dev/null 2>&1; then
    if [[ -n "$ZIPFILE" && -f "$ZIPFILE" ]]; then
      gh release create "$VERSION_TAG" ${ZIPFILE:+ "$ZIPFILE"} \
        --repo "$REPO_FULL" --title "$VERSION_TAG" --notes "$notes" || \
        die "Failed to create release via gh"
    else
      gh release create "$VERSION_TAG" --repo "$REPO_FULL" --title "$VERSION_TAG" --notes "$notes" || \
        die "Failed to create release via gh"
    fi
    return 0
  fi

  [[ -n "${GITHUB_TOKEN:-}" ]] || die "GITHUB_TOKEN not set; cannot create release without authenticated gh"
  local API_URL="https://api.github.com"
  local RESP
  RESP=$(curl -sS -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
               -H "Accept: application/vnd.github+json" \
               "$API_URL/repos/${REPO_FULL}/releases" \
               -d "{\"tag_name\":\"$VERSION_TAG\",\"name\":\"$VERSION_TAG\",\"body\":\"$(printf '%s' "$notes" | sed 's/\"/\\\"/g')\",\"draft\":false,\"prerelease\":false}")
  local UPLOAD_URL
  UPLOAD_URL=$(echo "$RESP" | grep -oE '"upload_url":\s*"[^"]+' | sed 's/"upload_url":\s*"//; s/{.*$//')
  [[ -n "$UPLOAD_URL" ]] || { echo "$RESP" >&2; die "Failed to create release via API"; }
  if [[ -n "$ZIPFILE" && -f "$ZIPFILE" ]]; then
    local FILENAME
    FILENAME="$(basename "$ZIPFILE")"
    curl -sS -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
         -H "Content-Type: application/zip" \
         --data-binary @"$ZIPFILE" \
         "${UPLOAD_URL}?name=${FILENAME}" >/dev/null || \
         die "Failed to upload asset"
  fi
}

create_release
info "Done. Repo: https://github.com/${REPO_FULL}  Tag: ${VERSION_TAG}"
