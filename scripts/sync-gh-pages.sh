#!/usr/bin/env bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"
REPO_URL="${REPO_URL:-https://kgrubb.github.io/stalwart-helm-chart}"
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
MODE="${1:-static}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git -c advice.detachedHead=false clone --branch gh-pages --depth 1 \
  "https://x-access-token:${TOKEN}@github.com/${REPO}.git" "$work/gh-pages"

cp pages/* "$work/gh-pages/"

if [[ "$MODE" == "full" ]]; then
  cd "$work/gh-pages"
  shopt -s nullglob
  for tag in $(gh release list --repo "$REPO" --limit 100 --json tagName -q '.[].tagName'); do
    gh release download "$tag" --repo "$REPO" -D . --pattern '*.tgz' --clobber
  done
  helm repo index . --url "$REPO_URL"
fi

cd "$work/gh-pages"
git add -A
git diff --staged --quiet && exit 0
git -c user.name="github-actions[bot]" \
  -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -m "Sync gh-pages assets"
git push
