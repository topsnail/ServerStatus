#!/usr/bin/env bash
# 只备份 .env + data/（配置与月流量统计）
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_DIR"

mkdir -p backups
stamp="$(date +%Y%m%d-%H%M%S)"
out="backups/serverstatus-${stamp}.tar.gz"

if [[ ! -f .env ]]; then
  echo "ERROR: 缺少 .env"
  exit 1
fi
if [[ ! -d data ]]; then
  echo "ERROR: 缺少 data/"
  exit 1
fi

# 尽量先让容器刷盘（stats 约 60s 写一次；reload 不保证立刻落盘，故停机备份更稳）
echo "==> 打包 .env + data/ → ${out}"
tar -czf "$out" .env data

echo "Backup OK: $out"
ls -lh "$out"
