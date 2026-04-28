#!/usr/bin/env bash
set -e

# 说明：本脚本用于初始化项目骨架。
# 设计原则：
# 1) 不删除任何文件；
# 2) 不覆盖任何已存在文件；
# 3) 已存在时只提示；
# 4) 所有路径均使用双引号，避免路径中包含特殊字符导致问题。

# 定义目录创建函数：若目录不存在则创建，存在则提示。
ensure_dir() {
  local dir_path="$1"

  # 若目录已存在，按要求输出存在提示并返回。
  if [ -d "$dir_path" ]; then
    echo "[exists-dir]  $dir_path"
    return
  fi

  # 若目录不存在，则创建并输出创建提示。
  mkdir -p "$dir_path"
  echo "[created-dir] $dir_path"
}

# 定义文件创建函数：若文件不存在则创建空文件，存在则提示。
ensure_file() {
  local file_path="$1"

  # 若文件已存在，按要求输出存在提示并返回。
  if [ -f "$file_path" ]; then
    echo "[exists-file] $file_path"
    return
  fi

  # 若文件不存在，创建空文件并输出创建提示。
  : > "$file_path"
  echo "[created-file] $file_path"
}

# 创建 Round 0 所需目录。
ensure_dir "docs"
ensure_dir "scripts"
ensure_dir "configs"
ensure_dir "configs/server"
ensure_dir "configs/client"
ensure_dir "templates"
ensure_dir "nodes"
ensure_dir "logs"
ensure_dir "backups"

# 创建 Round 0 所需基础文件（不覆盖已存在内容）。
ensure_file "README.md"
ensure_file ".gitignore"
ensure_file ".env.example"
ensure_file "docs/00_project_overview.md"
ensure_file "docs/01_terms.md"
ensure_file "docs/02_architecture.md"
ensure_file "docs/03_security_notes.md"
ensure_file "docs/round_notes.md"
ensure_file "scripts/init_project.sh"
ensure_file "scripts/snapshot_tree.sh"
ensure_file "configs/server/.gitkeep"
ensure_file "configs/client/.gitkeep"
ensure_file "templates/.gitkeep"
ensure_file "nodes/.gitkeep"
ensure_file "logs/.gitkeep"
ensure_file "backups/.gitkeep"

# 输出完成提示。
echo "[done] project skeleton initialized"
