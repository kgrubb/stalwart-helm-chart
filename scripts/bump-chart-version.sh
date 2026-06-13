#!/usr/bin/env bash
set -euo pipefail

CHART_FILE="charts/stalwart/Chart.yaml"
BEFORE_SHA="${1:?before sha required}"
AFTER_SHA="${2:?after sha required}"

current_version=$(awk '/^version:/ { print $2 }' "$CHART_FILE")

bump_level="patch"
breaking_re='^[a-zA-Z]+(\([^)]+\))?!:'
feat_re='^feat(\([^)]+\))?:'

while IFS= read -r subject; do
  [[ -z "$subject" || "$subject" =~ ^chore\(release\): ]] && continue

  if [[ "$subject" =~ BREAKING[[:space:]]CHANGE ]] || [[ "$subject" =~ $breaking_re ]]; then
    bump_level="major"
    break
  fi

  if [[ "$subject" =~ $feat_re ]] && [[ "$bump_level" != "major" ]]; then
    bump_level="minor"
  fi
done < <(git log --format=%s "${BEFORE_SHA}..${AFTER_SHA}")

IFS='.' read -r major minor patch <<< "$current_version"
case "$bump_level" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
esac

new_version="${major}.${minor}.${patch}"
[[ "$new_version" == "$current_version" ]] && exit 0

sed -i "s/^version: .*/version: ${new_version}/" "$CHART_FILE"
echo "Bumped chart version: ${current_version} -> ${new_version} (${bump_level})"
