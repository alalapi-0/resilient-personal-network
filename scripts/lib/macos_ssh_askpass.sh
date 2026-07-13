#!/usr/bin/env bash
set -euo pipefail

PROMPT="${1:-请输入 SSH 密码}"
DISPLAY_PROMPT="请输入 SSH 密码或本机私钥密码短语。"

if [[ "$PROMPT" == *"passphrase for key"* ]]; then
  DISPLAY_PROMPT="请输入本机 SSH 私钥密码短语。"
elif [[ "$PROMPT" == *@* && "$PROMPT" == *"password"* ]]; then
  DISPLAY_PROMPT="请输入远程服务器 SSH 密码。"
fi

/usr/bin/osascript - "$DISPLAY_PROMPT" <<'APPLESCRIPT'
on run argv
set dialogText to item 1 of argv
display dialog dialogText default answer "" with hidden answer buttons {"取消", "确定"} default button "确定" cancel button "取消" with title "SSH Password"
text returned of result
end run
APPLESCRIPT
