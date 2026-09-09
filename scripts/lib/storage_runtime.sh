#!/bin/bash
# Local storage-governance route: no PATH or internal binary fallback.
# Source only; does not read connection configuration or start a network service.
rpn_storage_prepare() {
  local rpn_script_root rpn_repo_root rpn_guard rpn_requested
  rpn_script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
  rpn_repo_root="$(cd "$rpn_script_root/.." && pwd -P)"
  rpn_guard=/Users/alalapi/.config/storage-governance/guard.sh
  RPN_RUNTIME_ROOT=/Volumes/AI_WORK_SSD/Runtimes/resilient-personal-network
  RPN_ACTUAL_BINARY="$RPN_RUNTIME_ROOT/sing-box"
  RPN_TEMP_ROOT=/Volumes/AI_WORK_SSD/Temp/resilient-personal-network
  rpn_requested="${SING_BOX_BIN:-}"
  case "$rpn_requested" in
    ""|"$RPN_ACTUAL_BINARY"|"$rpn_script_root/external-sing-box"|"$rpn_repo_root/tools/sing-box/sing-box") ;;
    *) echo '[error] sing-box override is outside the registered external route' >&2; return 78 ;;
  esac
  /bin/zsh -f "$rpn_guard" --check >/dev/null || return 78
  /usr/bin/ruby - "$RPN_RUNTIME_ROOT" "$RPN_ACTUAL_BINARY" "$RPN_TEMP_ROOT" <<'RUBY'
volume = '/Volumes/AI_WORK_SSD'
device = File.stat(volume).dev
ARGV.each do |path|
  abort '[error] external runtime path is missing or redirected' unless File.exist?(path) && File.realpath(path) == path
  abort '[error] external runtime path changed device' unless File.stat(path).dev == device
end
abort '[error] sing-box runtime is not executable' unless File.file?(ARGV[1]) && File.executable?(ARGV[1])
abort '[error] external temporary root missing' unless File.directory?(ARGV[2])
RUBY
  if [ "$?" -ne 0 ]; then return 78; fi
  SING_BOX_BIN="$rpn_script_root/external-sing-box"
  TMPDIR="$RPN_TEMP_ROOT"
  export SING_BOX_BIN TMPDIR
}
