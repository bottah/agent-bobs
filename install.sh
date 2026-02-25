#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-.}"

if [[ "$TARGET" == "." || "$TARGET" == "$SCRIPT_DIR" ]]; then
  echo "Error: target directory cannot be the template repo itself"
  exit 1
fi

if [[ ! -d "$TARGET" ]]; then
  echo "Error: target directory does not exist: $TARGET"
  exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"

echo "Installing agent-teams template into: $TARGET"

# Everything except repo infrastructure and runtime artifacts
exclude=(
  --exclude='.git'
  --exclude='install.sh'
  --exclude='.claude/audit.log'
  --exclude='.claude/settings.local.json'
)

# rsync preserves directory structure, only copies what changed
rsync -a "${exclude[@]}" "$SCRIPT_DIR/" "$TARGET/"

# Ensure hook scripts are executable
chmod +x "$TARGET"/scripts/hooks/*.sh 2>/dev/null || true

echo "Done."
echo ""
echo "Next steps:"
echo "  cd $TARGET"
echo "  git diff                  # review changes"
echo "  git add -A && git commit  # accept all"
echo "  git checkout -- .         # reject all"
