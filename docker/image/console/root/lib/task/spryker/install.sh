#!/bin/bash

function task_spryker_install()
{
    PGPASSWORD="$DB_PASS" FEATURE_ENABLE_ALL_STORES=no passthru vendor/bin/install -r docker -x frontend
}
