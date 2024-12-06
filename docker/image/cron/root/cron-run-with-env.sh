#!/bin/bash
command="$1"
output_file_name="$2"
env_vars=()
readarray -t env_vars < /app/env.sh
echo -e "■ [$(date '+%d/%m/%Y %H:%M:%S')] > $1" >> "/var/log/crons/$output_file_name"
/usr/bin/env - "${env_vars[@]}" su -s /bin/bash -p -c "cd /app; $command" www-data >> "/var/log/crons/$output_file_name" 2>&1
