#!/bin/sh
# One-shot 0.16 store -> empty 1.0 store via stalwart-migrate (server must be stopped).
set -eu
STATE=/var/lib/stalwart-migrate
rm -rf "$STATE" && mkdir -p "$STATE"
printf '%s\n' "${SOURCE_JSON:?}" >/tmp/source.json
printf '%s\n' "${TARGET_JSON:?}" >/tmp/target.json
cp /answers/answers.toml "$STATE/answers.toml"
stalwart-migrate prepare --non-interactive \
  --source /tmp/source.json \
  --state "$STATE"
stalwart-migrate run --final --yes \
  --source /tmp/source.json \
  --target /tmp/target.json \
  --state "$STATE"
echo "v1 migration ok"
