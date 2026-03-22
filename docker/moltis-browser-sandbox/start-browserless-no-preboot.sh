#!/bin/sh
set -eu

# Moltis 0.10.18 still bind-mounts /data/browser-profile for sibling browser
# containers even when persist_profile=false. browserless/chrome fails during
# preboot on that mount path, so force lazy Chrome startup until upstream fixes
# the runtime contract.
export PREBOOT_CHROME=false

cd /usr/src/app
exec ./start.sh
