#!/bin/bash

# extracts log files and archive them
function task_ci_archive_logs() {
    shopt -s globstar
    ls data/**/*.log | xargs -I {} sh -c 'mkdir -p "/tmp/artifacts/$(dirname {})"'
    ls data/**/*.log | xargs -I {} sh -c 'cp {} "/tmp/artifacts/$(dirname {})/"'
}
