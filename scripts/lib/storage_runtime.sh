#!/bin/bash
# Source-only dispatcher. Each platform keeps its own registered storage route.
rpn_storage_prepare() {
  local rpn_script_root rpn_requested
  rpn_script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
  case "$(/usr/bin/uname -s)" in
    Darwin)
      source "$rpn_script_root/lib/storage_runtime_macos.sh" || return 78
      rpn_storage_prepare
      ;;
    Linux)
      rpn_requested="${SING_BOX_BIN:-}"
      /usr/bin/python3 -I "$rpn_script_root/lib/linux_storage_runtime.py" "$rpn_script_root" "$rpn_requested" || return 78
      RPN_RUNTIME_ROOT=/home/alalapi/Runtimes/resilient-personal-network
      RPN_ACTUAL_BINARY="$RPN_RUNTIME_ROOT/sing-box"
      RPN_TEMP_ROOT=/home/alalapi/Temp/resilient-personal-network
      RPN_CACHE_ROOT=/home/alalapi/Caches/resilient-personal-network
      SING_BOX_BIN="$rpn_script_root/external-sing-box"
      TMPDIR="$RPN_TEMP_ROOT"
      XDG_CACHE_HOME="$RPN_CACHE_ROOT"
      export SING_BOX_BIN TMPDIR XDG_CACHE_HOME
      ;;
    *) echo '[error] unregistered runtime platform' >&2; return 78 ;;
  esac
}
