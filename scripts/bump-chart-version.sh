#!/usr/bin/env bash
# Bump charts/stalwart/Chart.yaml version from conventional commit messages.
# Usage: bump-chart-version.sh <before_sha> <after_sha>
set -euo pipefail

CHART_FILE="charts/stalwart/Chart.yaml"
BEFORE_SHA="${1:?before sha required}"
AFTER_SHA="${2:?after sha required}"

if [[ ! -f "$CHART_FILE" ]]; then
  echo "Chart file not found: $CHART_FILE" >&2
  exit 1
fi

current_version=$(awk '/^version:/ { print $2 }' "$CHART_FILE")

bump_level="patch"
while IFS= read -r subject; do
  [[ -z "$subject" ]] && continue

  if [[ "$subject" =~ BREAKING[[:space:]]CHANGE ]] || [[ "$subject" =~ ^[a-zA-Z]+(\([^)]+\))?!: ]]; then
    bump_level="major"
    break
  fi

  if [[ "$subject" =~ ^feat(\([^)]+\))?: ]]; then
    if [[ "$bump_level" != "major" ]]; then
      bump_level="minor"
    fi
  fi
done < <(git log --format=%s "${BEFORE_SHA}..${AFTER_SHA}")

IFS='.' read -r major minor patch <<< "$current_version"
major=${major:-0}
minor=${minor:-0}
patch=${patch:-0}

case "$bump_level" in
  major)
    major=$((major + 1))
    minor=0
    patch=0
    ;;
  minor)
    minor=$((minor + 1))
    patch=0
    ;;
  patch)
    patch=$((patch + 1))
    ;;
esac

new_version="${major}.${minor}.${patch}"

if [[ "$new_version" == "$current_version" ]]; then
  echo "Chart version unchanged: $current_version"
  exit 0
fi

sed -i "s/^version: .*/version: ${new_version}/" "$CHART_FILE"
echo "Bumped chart version: ${current_version} -> ${new_version} (${bump_level})"
