#!/bin/bash
# Delete .log files in /var/log/app that are older than 7 days.
set -e

LOG_DIR=/var/log/app

[ -d "$LOG_DIR" ] || exit 0

find "$LOG_DIR" -type f -name "*.log" -mtime +7 -print -delete