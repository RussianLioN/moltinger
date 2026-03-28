#!/usr/bin/env sh
set -eu

profile_dir="${MOLTIS_BROWSER_PROFILE_DIR:-/data/browser-profile}"
runtime_home="${MOLTIS_BROWSER_RUNTIME_HOME:-/tmp/moltis-browser-home}"

mkdir -p "$runtime_home"
chown 999:999 "$runtime_home"
chmod 0770 "$runtime_home"

if [ -d "$profile_dir" ]; then
  chown -R 999:999 "$profile_dir"
  chmod 0770 "$profile_dir"
fi

export HOME="$runtime_home"
exec setpriv --reuid=999 --regid=999 --init-groups /bin/sh -lc 'cd /usr/src/app && exec ./start.sh'
