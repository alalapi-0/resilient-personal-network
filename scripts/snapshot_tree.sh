#!/usr/bin/env bash
set -e

# 说明：本脚本用于生成当前项目结构快照，输出到 docs/tree_snapshot.txt。
# 设计要点：
# 1) 优先使用 tree 命令；
# 2) 无 tree 时使用 find 回退；
# 3) 不写入 .git 目录；
# 4) 不展开 logs 与 backups 的真实内容（仅显示目录本身及 .gitkeep）。

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
  # 使用 tree 生成结构，过滤 .git；
  # 同时通过 -I 排除 logs/backups 下的非 .gitkeep 内容。
  {
    echo
    tree -a \
      --noreport \
      -I '.git|logs/*|backups/*' \
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
  # - 排除 .git 整个目录；
  # - 对 logs/backups，仅保留目录本身和 .gitkeep。
  {
    echo
    find . \
      -path './.git' -prune -o \
      -path './logs/*' ! -name '.gitkeep' -prune -o \
      -path './backups/*' ! -name '.gitkeep' -prune -o \
      -print | sort
  } >> "$snapshot_file"
fi

# 输出完成提示。
echo "[done] snapshot saved to docs/tree_snapshot.txt"
