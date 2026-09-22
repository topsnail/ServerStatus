#!/usr/bin/env bash
# ServerStatus 生产部署：拉代码 → 构建镜像 → 重启容器 → 健康检查
# 绝不覆盖：.env、data/
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_DIR"

# --project-directory 固定为仓库根，避免 -f deploy/... 时读错 .env 位置
COMPOSE=(docker compose --project-directory "$APP_DIR" -f "$APP_DIR/deploy/docker-compose.yml")
BRANCH="${DEPLOY_BRANCH:-master}"
HEALTH_URL="${DEPLOY_HEALTH_URL:-http://127.0.0.1:8080/api/health}"
SKIP_GIT="${DEPLOY_SKIP_GIT:-0}"

echo "==> cwd: $APP_DIR"

if [[ ! -f .env ]]; then
  echo "ERROR: 缺少 .env。请先：cp deploy/env.example .env 并填写 ADMIN_TOKEN"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: 未找到 docker 命令"
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: 未找到 docker compose 插件"
  exit 1
fi

mkdir -p data backups
if [[ ! -f data/config.json ]]; then
  echo "==> 首次初始化：复制 server/config.json → data/config.json"
  cp server/config.json data/config.json
fi

# 必须是普通文件；若曾误启动过 Compose，Docker 可能建成同名目录
if [[ -d data/config.json ]]; then
  echo "ERROR: data/config.json 是目录（常见于文件尚未创建就 compose up）。请删掉该目录后重跑："
  echo "  rm -rf data/config.json && cp server/config.json data/config.json"
  exit 1
fi

if [[ "$SKIP_GIT" != "1" ]]; then
  echo "==> git fetch / reset → origin/${BRANCH}"
  git fetch origin
  git checkout "$BRANCH"
  git reset --hard "origin/${BRANCH}"
else
  echo "==> 跳过 git 更新（DEPLOY_SKIP_GIT=1）"
fi

echo "==> docker compose build"
"${COMPOSE[@]}" build

echo "==> docker compose up -d"
"${COMPOSE[@]}" up -d --remove-orphans

echo "==> 等待健康检查 ${HEALTH_URL}"
ok=0
for _ in $(seq 1 45); do
  if curl -sf "$HEALTH_URL" >/dev/null; then
    ok=1
    break
  fi
  sleep 2
done

if [[ "$ok" -ne 1 ]]; then
  echo "ERROR: 健康检查失败"
  "${COMPOSE[@]}" ps || true
  docker logs --tail 80 serverstatus-server || true
  exit 1
fi

echo "Deploy OK"
curl -s "$HEALTH_URL" || true
echo
