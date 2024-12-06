#!/bin/bash

# wait for file
function task_file_wait() {
    echo -e "Waiting for file $1 to be available"

    local counter=0

    while ! test -f $1; do

        if (( counter > 180 )); then
            (>&2 echo "timeout while waiting on $1 to become available")
            exit 1
        fi

        sleep 10
        ((++counter))
    done
}

task_file_wait /app/.my127ws/.flag-built

source /entrypoint.dynamic.sh
