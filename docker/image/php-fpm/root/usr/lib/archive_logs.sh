#!/bin/bash

# extracts log files and archive them
mkdir /tmp/artifacts
find data -name "*.log" -exec sh -c 'mkdir -p /tmp/artifacts/$(dirname {})' \;
find data -name "*.log" -exec sh -c 'cp {} "/tmp/artifacts/$(dirname {})/"' \;
