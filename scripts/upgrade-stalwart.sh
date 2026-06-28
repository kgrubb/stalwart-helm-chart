#!/usr/bin/env bash
set -euo pipefail

chart="charts/stalwart/Chart.yaml"
values="charts/stalwart/values.yaml"

current=$(awk '/^appVersion:/ { gsub(/"/, "", $2); print $2 }' "$chart")
latest=$(gh api repos/stalwartlabs/stalwart/releases/latest --jq .tag_name)

current="${current#v}"
latest="${latest#v}"

if [[ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -1)" == "$current" ]]; then
  exit 0
fi

IFS='.' read -r cur_maj cur_min _ <<< "$current"
IFS='.' read -r new_maj new_min _ <<< "$latest"

if (( new_maj > cur_maj )); then
  prefix="feat!"
elif (( new_min > cur_min )); then
  prefix="feat"
else
  prefix="fix"
fi

tag="v${latest}"
sed -i "s/^appVersion: .*/appVersion: \"${tag}\"/" "$chart"
sed -i "s|^  tag: .*|  tag: \"${tag}\"|" "$values"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "upgraded=true"
    echo "stalwart_version=${tag}"
    echo "commit_prefix=${prefix}"
  } >> "$GITHUB_OUTPUT"
fi
