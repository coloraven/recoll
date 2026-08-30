#!/usr/bin/env bash
# Download the latest successful "recoll-windows-gui" artifact into ./dist
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required. Install: scoop install gh" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Not logged in to GitHub. Run: gh auth login" >&2
  exit 1
fi

mkdir -p dist
rm -rf dist/.download
mkdir -p dist/.download

echo "Finding latest successful CI run with recoll-windows-gui artifact..."
RUN_ID=$(gh run list --workflow=ci.yml --branch main --status success --limit 20 \
  --json databaseId,conclusion,displayTitle,headSha \
  --jq '.[0].databaseId')

if [ -z "${RUN_ID}" ] || [ "${RUN_ID}" = "null" ]; then
  echo "No successful CI run found yet." >&2
  exit 1
fi

echo "Downloading artifact from run ${RUN_ID}..."
gh run download "${RUN_ID}" -n recoll-windows-gui -D dist/.download

# Flatten into dist/
find dist/.download -type f \( -name '*.zip' -o -name '*.exe' \) -exec cp -f {} dist/ \;
rm -rf dist/.download

echo "Artifacts in dist/:"
ls -lh dist/
