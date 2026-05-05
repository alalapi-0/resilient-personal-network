#!/usr/bin/env bash
set -e

# 说明：本脚本用于生成当前项目结构快照，输出到 docs/tree_snapshot.txt。
# 设计要点：
# 1) 优先使用 tree 命令；
# 2) 无 tree 时使用 find 回退；
# 3) 不写入 .git、本地 IDE 配置目录和 macOS 临时文件；
# 4) 不展开 logs、backups 与真实 configs 内容（仅显示目录本身及 .gitkeep）。

# 定义快照输出文件路径。
snapshot_file="docs/tree_snapshot.txt"

# 确保 docs 目录存在，避免重定向失败。
mkdir -p "docs"

# 先写入固定标题与生成时间（UTC）。
{
  echo "# Tree Snapshot"
  echo "Generated at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
} > "$snapshot_file"

# 判断系统是否存在 tree 命令。
if command -v tree >/dev/null 2>&1; then
  # 使用 tree 生成结构，过滤 .git、.idea 与 .DS_Store；
  # 同时通过 -I 排除 logs/backups/configs 下的真实内容。
  {
    echo
    tree -a \
      --noreport \
      -I '.git|.idea|.DS_Store|logs/*|backups/*|configs/server/*.json|configs/client/*.json|configs/client/*.txt|configs/client/*.yaml|configs/client/*.yml' \
      .
  } >> "$snapshot_file"

  # 手动补回 logs/.gitkeep 与 backups/.gitkeep（若存在），保证可见性。
  {
    if [ -f "logs/.gitkeep" ]; then
      echo "./logs/.gitkeep"
    fi
    if [ -f "backups/.gitkeep" ]; then
      echo "./backups/.gitkeep"
    fi
  } >> "$snapshot_file"
else
  # tree 不存在时，使用 find 回退。
  # 过滤规则：
  # - 排除 .git 与 .idea 整个目录；
  # - 排除 macOS 自动生成的 .DS_Store；
  # - 对 logs/backups/configs，仅保留目录本身和 .gitkeep。
  {
    echo
    find . \
      -path './.git' -prune -o \
      -path './.idea' -prune -o \
      -name '.DS_Store' -prune -o \
      -path './logs/*' ! -name '.gitkeep' -prune -o \
      -path './backups/*' ! -name '.gitkeep' -prune -o \
      -path './configs/server/*' ! -name '.gitkeep' -prune -o \
      -path './configs/client/*' ! -name '.gitkeep' -prune -o \
      -print | sort
  } >> "$snapshot_file"
fi

# 输出完成提示，保持与验收标准一致。
echo "[done] snapshot saved"
