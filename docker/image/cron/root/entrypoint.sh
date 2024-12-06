#!/bin/bash

# this is used to load env vars in crontab commands
env | grep -v "affinity:container" | awk -F= '{print "export",$1"=""\""$2"\""}' > /env.sh

# setup crontab
echo 'MAILTO=""' > /crontab
php /app/bin/generate-crons.php >> /crontab
mkdir -p /var/log/crons

# run
crontab /crontab
exec cron -f -L 15
