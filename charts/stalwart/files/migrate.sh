#!/bin/sh
# One-shot RocksDB PVC -> shared DataStore (server must be stopped).
set -eu
DUMP=/export/dump
printf '%s\n' '{"@type":"RocksDb","path":"/var/lib/stalwart"}' >/tmp/rocksdb.json
printf '%s\n' "${STORE_JSON:?}" >/tmp/store.json
rm -rf "$DUMP" && mkdir -p "$DUMP"
stalwart --config /tmp/rocksdb.json --export "$DUMP"
test "$(find "$DUMP" -type f | wc -l)" -gt 0
stalwart --config /tmp/store.json --import "$DUMP"
echo "migration ok"
