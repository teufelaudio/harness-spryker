#!/bin/bash

set -e
set -o pipefail

ES_REPO_PATH='/tmp/elasticsearch/backup'

function extract_and_import_snapshot() {
  cd /tmp/elasticsearch/ && tar xzf es.tar.gz && rm -rf backup && mv es backup && chown -R elasticsearch:elasticsearch .
  curl -XPUT http://localhost:9200/_snapshot/backup -H "Content-Type: application/json" -d "{\"type\": \"fs\",\"settings\": {\"location\": \"$ES_REPO_PATH\",\"compress\": true}}"
  curl -XPOST "localhost:9200/_all/_close?allow_no_indices=true&expand_wildcards=all"
  curl -XPOST http://localhost:9200/_snapshot/backup/snapshot_1/_restore
}

extract_and_import_snapshot
