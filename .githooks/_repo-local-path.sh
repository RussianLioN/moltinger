#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel)}"

if [[ -d "${PROJECT_ROOT}/bin" && ":${PATH}:" != *":${PROJECT_ROOT}/bin:"* ]]; then
  export PATH="${PROJECT_ROOT}/bin:${PATH}"
fi
