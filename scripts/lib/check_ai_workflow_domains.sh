#!/usr/bin/env bash
# 说明：检查客户端分流规则是否包含 AI 工作流必需域名（见 docs/28_ai_workflow_priority.md）。
# 用法：source 后调用 check_singbox_ai_workflow_domains "$CONFIG_FILE"
#       或 check_shadowrocket_ai_workflow_domains "$CONF_FILE"

AI_WORKFLOW_DOMAIN_SUFFIXES=(
  openai.com
  chatgpt.com
  oaistatic.com
  oaiusercontent.com
  openrouter.ai
  cursor.com
  cursor.sh
  anthropic.com
  claude.ai
  google.com
  googleapis.com
  gstatic.com
  github.com
  githubusercontent.com
  githubassets.com
  githubcopilot.com
)

_domain_suffix_covers() {
  local expected="$1"
  local suffix="$2"
  if [ "$suffix" = "$expected" ]; then
    return 0
  fi
  case "$expected" in
    *."$suffix") return 0 ;;
  esac
  return 1
}

_domain_exact_covers() {
  local expected="$1"
  local domain="$2"
  if [ "$domain" = "$expected" ]; then
    return 0
  fi
  case "$expected" in
    *."$domain") return 0 ;;
  esac
  return 1
}

_is_ai_domain_covered() {
  local expected="$1"
  local suffix domain
  for suffix in "${SINGBOX_SUFFIXES[@]:-}"; do
    if _domain_suffix_covers "$expected" "$suffix"; then
      return 0
    fi
  done
  for domain in "${SINGBOX_DOMAINS[@]:-}"; do
    if _domain_exact_covers "$expected" "$domain"; then
      return 0
    fi
  done
  return 1
}

check_singbox_ai_workflow_domains() {
  local config_file="$1"
  local expected missing_count=0
  local entry

  SINGBOX_SUFFIXES=()
  SINGBOX_DOMAINS=()
  while IFS= read -r entry; do
    [ -n "$entry" ] && SINGBOX_SUFFIXES+=("$entry")
  done < <(jq -r '[.route.rules[]? | select(.outbound? == "proxy") | .domain_suffix[]? // empty] | .[]' "$config_file")
  while IFS= read -r entry; do
    [ -n "$entry" ] && SINGBOX_DOMAINS+=("$entry")
  done < <(jq -r '[.route.rules[]? | select(.outbound? == "proxy") | .domain[]? // empty] | .[]' "$config_file")

  echo "== ai workflow routing =="
  for expected in "${AI_WORKFLOW_DOMAIN_SUFFIXES[@]}"; do
    if _is_ai_domain_covered "$expected"; then
      echo "[ok] 路由规则覆盖：$expected"
    else
      echo "[warn] 路由规则缺少 AI 工作流域名：$expected"
      missing_count=$((missing_count + 1))
    fi
  done

  if [ "$missing_count" -gt 0 ]; then
    echo "[warn] 发现 $missing_count 个 AI 工作流域名未显式代理，建议重新运行 scripts/generate_singbox_config.sh"
    return 1
  fi
  echo "[ok] AI 工作流域名分流规则完整"
  return 0
}

check_shadowrocket_ai_workflow_domains() {
  local conf_file="$1"
  local expected missing_count=0
  local line rule_domain rule_suffix rule_policy

  echo "== ai workflow routing =="
  for expected in "${AI_WORKFLOW_DOMAIN_SUFFIXES[@]}"; do
    local covered=0
    while IFS= read -r line; do
      rule_domain="${line#DOMAIN,}"
      rule_domain="${rule_domain%,*}"
      rule_suffix="${line#DOMAIN-SUFFIX,}"
      rule_suffix="${rule_suffix%,*}"
      rule_policy="${line##*,}"
      if { [ "$rule_domain" = "$expected" ] || [ "$rule_suffix" = "$expected" ]; } \
        && [ "$rule_policy" = "proxy" ]; then
        covered=1
        break
      fi
    done < <(grep -E '^(DOMAIN|DOMAIN-SUFFIX),' "$conf_file" || true)

    if [ "$covered" -eq 1 ]; then
      echo "[ok] 路由规则覆盖：$expected"
    else
      echo "[warn] 路由规则缺少 AI 工作流域名：$expected"
      missing_count=$((missing_count + 1))
    fi
  done

  if [ "$missing_count" -gt 0 ]; then
    echo "[warn] 发现 $missing_count 个 AI 工作流域名未显式代理，建议重新运行 scripts/generate_shadowrocket_macos_config.sh"
    return 1
  fi
  echo "[ok] AI 工作流域名分流规则完整"
  return 0
}
