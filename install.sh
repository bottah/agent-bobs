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

echo "Installing agent-bobs template into: $TARGET"

# Repo infrastructure and runtime artifacts
exclude=(
  --exclude='.git'
  --exclude='install.sh'
  --exclude='.claude/audit.log'
  --exclude='.claude/settings.local.json'
  --exclude='.claude/last-session.json'
  --exclude='.claude/subagent.log'
  --exclude='.claude/transcript-backups'
  --exclude='docs/handoff-*.md'
)

# Project-specific files that are customized after initial install.
# Only copy these if they don't already exist in the target.
customize_once=(
  README.md
  CHANGELOG.md
  CLAUDE.md
  .github/workflows/ci.yml
  .github/ruleset.json
)

for f in "${customize_once[@]}"; do
  if [[ -e "$TARGET/$f" ]]; then
    exclude+=(--exclude="$f")
  fi
done

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
