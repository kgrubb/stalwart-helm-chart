#!/usr/bin/env bash
set -euo pipefail

SINCE="${1:?since ref required}"
UNTIL="${2:?until sha required}"
VERSION="${3:?version required}"

REPO="${GITHUB_REPOSITORY:-}"
if [[ -z "$REPO" ]]; then
  REPO=$(git remote get-url origin | sed -E 's#.*github.com[:/](.+)$#\1#' | sed 's/\.git$//')
fi
CHANGELOG="CHANGELOG.md"
NOTES="charts/stalwart/RELEASE-NOTES.md"
DATE=$(date -u +%Y-%m-%d)

added=()
fixed=()
changed=()

section_for() {
  case "$1" in
    feat!*|*!:*|*BREAKING*) echo changed ;;
    feat:*) echo added ;;
    fix:*) echo fixed ;;
    perf:*|refactor:*|chore:*|docs:*|ci:*) echo changed ;;
  esac
}

pr_numbers_since() {
  git log "${SINCE}..${UNTIL}" --pretty=format:'%s' \
    | grep -v '^chore(release):' \
    | grep -oE '#[0-9]+' \
    | tr -d '#' \
    | sort -nu
}

append() {
  local section="$1" line="$2"
  case "$section" in
    added) added+=("$line") ;;
    fixed) fixed+=("$line") ;;
    changed) changed+=("$line") ;;
  esac
}

summary_bullets() {
  gh pr view "$1" --repo "$REPO" --json body -q .body | awk '
    /^## Summary/ { found=1; next }
    /^## / { if (found) exit }
    found && /^- / { sub(/^- /, ""); print }
  '
}

while read -r num; do
  [[ -z "$num" ]] && continue
  title=$(gh pr view "$num" --repo "$REPO" --json title -q .title)
  section=$(section_for "$title")
  [[ -n "$section" ]] || continue

  url="https://github.com/${REPO}/pull/${num}"
  mapfile -t bullets < <(summary_bullets "$num")
  ((${#bullets[@]})) || bullets=("${title#*: }")

  if ((${#bullets[@]} == 1)); then
    append "$section" "- ${bullets[0]} ([#${num}](${url}))"
  else
    append "$section" "- ${title#*: } ([#${num}](${url}))"
    for line in "${bullets[@]}"; do
      append "$section" "  - ${line}"
    done
  fi
done < <(pr_numbers_since)

if [[ ${#added[@]} -eq 0 && ${#fixed[@]} -eq 0 && ${#changed[@]} -eq 0 ]]; then
  changed=("- Chart update")
fi

{
  printf '## [%s] - %s\n\n' "$VERSION" "$DATE"
  [[ ${#added[@]} -gt 0 ]] && { printf '### Added\n'; printf '%s\n' "${added[@]}"; echo; }
  [[ ${#changed[@]} -gt 0 ]] && { printf '### Changed\n'; printf '%s\n' "${changed[@]}"; echo; }
  [[ ${#fixed[@]} -gt 0 ]] && { printf '### Fixed\n'; printf '%s\n' "${fixed[@]}"; echo; }
} > "$NOTES"

grep -q "^## \\[${VERSION}\\]" "$CHANGELOG" && exit 0

line=$(grep -n '^## \[Unreleased\]' "$CHANGELOG" | cut -d: -f1)
{
  head -n "$line" "$CHANGELOG"
  echo ""
  cat "$NOTES"
  echo ""
  tail -n +"$((line + 1))" "$CHANGELOG"
} > "${CHANGELOG}.new"
mv "${CHANGELOG}.new" "$CHANGELOG"
