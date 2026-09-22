# ServerStatus 自托管部署教程

轻量服务器探针与云监控面板：多节点在线状态、资源占用、三网延迟、服务监测、SSL 证书检查、Watchdog 告警、HTTP API 与 Web 配置管理。

> **读者**：可按本文从零部署（1Panel + Ubuntu + Docker）。适合小白，按顺序做即可。  
> **原则**：GitHub 自动部署（SSH）· 代码/数据/配置分离 · 一应用一目录 · 优先 Docker · 备份只留 `.env` + `data/`。  
> **原则补充**：不改业务代码；生产用 `deploy/docker-compose.yml`，运行时配置与统计落在 `data/`。  
> 命令可整行复制；每步有「成功」与「失败时」说明。仓库：`git@github.com:topsnail/ServerStatus.git`。  
> 生产域名：**https://s.joanan.cn**（1Panel 反代到 `http://127.0.0.1:8080`）。Agent 上报端口 **`35601/tcp`** 需对客户端可达。  
> 下文菜单与按钮按**中文界面**书写（**1Panel**、**GitHub**）。本机操作均在 **Windows**（PowerShell / 资源管理器 / 记事本）。每一步标题会标明在【服务器】【1Panel 网页】【GitHub 网页】还是【你的电脑】操作。

---

## 目录

1. #1-项目简介
2. #2-环境与原则
3. #3-目录说明
4. #4-本地开发
5. #5-首次部署
6. #6-环境变量
7. #7-github-自动部署
8. #8-备份与恢复及更换服务器
9. #9-常见问题
10. #附录命令速查

---

## 1. 项目简介

- 网页：节点总览、资源与流量、三网延迟、服务/证书/Watchdog 状态
- 管理：WebUI「配置」页或 HTTP API（需 `ADMIN_TOKEN`）增删节点、监测项、告警
- 客户端：各被监控机器上的 Agent，向服务端 `35601` 上报状态

| 层级 | 技术 |
|------|------|
| 服务端 | Go（`server/`），单二进制提供 WebUI + HTTP API + Agent TCP |
| 前端 | 静态 WebUI（`web/`，打进 Docker 镜像） |
| 配置 / 数据 | `data/config.json`（节点与监测配置）、`data/stats.json`（月流量等持久化） |
| 运行 | Docker Compose（生产用 `deploy/docker-compose.yml`） |

生产环境：**一个容器**监听容器内 `:80`（宿主机映射 `127.0.0.1:8080`）与 `:35601`。由 1Panel 反代 **https://s.joanan.cn** → `http://127.0.0.1:8080`。**每次发布**由 `scripts/deploy.sh` 拉代码、重建镜像并重启容器。

⚠️ **配置与代码分离**：仓库里的 `server/config.json` 只作模板；线上真正读写的是 `data/config.json`。自动部署 **`git reset` 不会动** `.env` 与 `data/`。

---

## 2. 环境与原则

### 2.1 版本（参考）

| 项目 | 要求 |
|------|------|
| 系统 | Ubuntu 24.04.5 LTS |
| Docker | ≥ 24（含 `docker compose` 插件） |
| 1Panel | 用「网站 / 反向代理 / 备份 / 防火墙」；**不要用**「进程守护」管本应用 |
| Git | 必需（参考 2.34.1） |
| 本机（可选） | Go ≥ 1.25、Docker Desktop（仅本地开发需要） |

### 2.2 五条原则 + 两套密钥

| 原则 | 本应用做法 |
|------|------------|
| GitHub 自动部署（SSH） | 推送到 `master` → GitHub「操作」经 SSH 登录服务器 → 只更新本目录代码 → 构建镜像 → 重启容器 |
| 代码 / 数据 / 配置分离 | 代码用 Git；密钥用 `.env`；配置与统计用 `data/`；自动部署**绝不覆盖**后两者 |
| 一应用一目录 | 本应用 `/apps/serverstatus`；其它应用用 `/apps/其它名`；HTTP `8080`；Agent `35601`；容器名 `serverstatus-server` |
| 优先 Docker | 用 Compose 跑官方 `Dockerfile.server`；不用 PM2 / 不用改业务源码 |
| 备份只管 data 和 .env | 源码靠 Git；镜像可重建 |

#### 两套密钥（提前搞懂，后面不绕）

| | 第一把：服务器拉 GitHub 代码 | 第二把：GitHub Actions 登录服务器 |
|--|------------------------------|-----------------------------------|
| 私钥在哪 | 【服务器】`~/.ssh/vps_github` | 【你的电脑】`vps_deploy`（桌面） |
| 公钥贴到哪 | 【GitHub 网页】账号 → **设置** → **SSH 和 GPG 密钥** | 【服务器】`~/.ssh/authorized_keys` |
| 干嘛用 | `git clone` / `git pull` | GitHub「操作」SSH 进服务器执行部署脚本 |
| 能否多仓库共用 | ✅ 账号密钥，所有仓库都能拉 | ✅ 同一把私钥可粘进多个仓库的机密 |

```text
日常更新流程：
【你的电脑】git push → 【GitHub 网页】触发「操作」
    → 用第二把钥匙 SSH 登录【服务器】
    → 【服务器】用第一把钥匙 git pull → docker build → compose up → 健康检查
```

---

## 3. 目录说明

```text
/apps/serverstatus/
├── .env                      ← 配置（要备份，不进 Git）：ADMIN_TOKEN 等
├── .gitignore                ← 必须忽略 .env、data/、backups/
├── data/                     ← 数据（要备份）
│   ├── config.json           ← 运行时主配置（WebUI/API 会改这里）
│   └── stats.json            ← 月流量与状态持久化（运行后出现）
├── backups/                  ← 备份脚本输出（可选）
├── deploy/
│   ├── docker-compose.yml    ← 生产编排（绑定 127.0.0.1:8080 + 35601）
│   └── env.example           ← .env 模板
├── scripts/
│   ├── deploy.sh             ← 自动/手动部署
│   └── backup.sh             ← 打包 .env + data/
├── server/ web/ clients/ …   ← 代码（Git / 自动部署更新）
├── Dockerfile.server         ← 服务端镜像
└── docker-compose-*.yml      ← 上游示例（本地试用可参考；生产用 deploy/）
```

| 路径 | 用途 |
|------|------|
| `data/config.json` | 节点、monitors、sslcerts、watchdog 等 |
| `data/stats.json` | 月流量等运行时统计 |
| `.env` | `ADMIN_TOKEN`、时区等 |
| `deploy/docker-compose.yml` | 生产 Compose，挂载 `data/` |

---

## 4. 本地开发

> 只在自己电脑上改代码、调试时看本节。**直接部署到服务器可跳过，从第 5 节开始。**

```bash
cp deploy/env.example .env
mkdir -p data
cp server/config.json data/config.json
docker compose --project-directory . -f deploy/docker-compose.yml up -d --build
```

**成功**：`http://127.0.0.1:8080/` 能开，`/api/health` 返回 JSON。

---

## 5. 首次部署

| 项 | 值 |
|----|-----|
| 目录 | `/apps/serverstatus` |
| HTTP | `127.0.0.1:8080`（反代目标） |
| Agent | `35601/tcp`（须防火墙放行） |
| 容器名 | `serverstatus-server` |
| 仓库 | `git@github.com:topsnail/ServerStatus.git` |
| 分支 | `master` |
| 域名 | `https://s.joanan.cn` |

| 本文写法 | 实际是哪里 |
|----------|------------|
| 【服务器】 | 云主机命令行（1Panel 终端或 SSH） |
| 【1Panel 网页】 | 浏览器打开 1Panel |
| 【GitHub 网页】 | github.com |
| 【你的电脑】 | Windows |

### 5.0 【你的电脑】动手前检查清单（必做）

| # | 检查项 | 怎么确认 |
|---|--------|----------|
| 1 | 本机有 `deploy/`、`scripts/`、`.github/workflows/deploy.yml` | 资源管理器能看到 |
| 2 | 已 **push 到 GitHub `master`** | 网页打开仓库能看到 `deploy` 文件夹 |
| 3 | `s.joanan.cn` 的 **A 记录**已指向服务器 IP | 域名控制台，或 `nslookup s.joanan.cn` |
| 4 | 将放行 `80`、`443`、`35601` | 云安全组 + 1Panel 防火墙 |

本机推送示例（仓库目录 PowerShell）：

```powershell
cd c:\vps\ServerStatus
git add deploy scripts .github/workflows/deploy.yml .gitignore jiaocheng.md
git commit -m "Add production deploy files and tutorial"
git push -u origin master
```

> GitHub 上还没有 `deploy/` 时，**不要开始 5.3**——服务器会克隆到旧代码。

---

### 5.1 【服务器】验证系统环境（已装则跳过）

```bash
command -v docker >/dev/null 2>&1 && echo "✅ Docker $(docker -v)" || echo "❌ Docker 未安装"
docker compose version >/dev/null 2>&1 && echo "✅ $(docker compose version)" || echo "❌ docker compose 未安装"
docker ps >/dev/null 2>&1 && echo "✅ docker 权限正常" || echo "❌ 无权限跑 docker（需加组或用 root）"
command -v git >/dev/null 2>&1 && git --version || echo "❌ Git 未安装"
command -v curl >/dev/null 2>&1 && echo "✅ curl" || echo "❌ curl 未安装"
ss -lntp | grep -E ':8080|:35601' || echo "✅ 8080 与 35601 暂未被占用"
```

缺什么补什么。1Panel 应用商店装 **Docker** 即可。无 docker 权限时：

```bash
sudo usermod -aG docker "$(whoami)"
# 重新登录后再测：docker ps
```

全部就绪：

```bash
docker -v && docker compose version && docker ps && git --version
```

---

### 5.2 【1Panel 网页】创建网站与反向代理

1. **网站** → **创建网站**  
2. 主域名：`s.joanan.cn`（不要加 `https://`）  
3. 类型「反向代理」，目标：`http://127.0.0.1:8080`（程序未启动时 **502 正常**）  
4. 申请 SSL，开启强制 HTTPS  
5. 放行 **80/443** 与 **`35601/tcp`**

**失败时**：证书失败 → A 记录未生效或 80 未通（回 5.0）。

---

### 5.3 【服务器】准备应用目录

```bash
sudo mkdir -p /apps/serverstatus
sudo chown -R "$(whoami):$(whoami)" /apps/serverstatus
cd /apps/serverstatus
pwd
```

若目录非空，先挪走再清空：

```bash
[ -f .env ] && mv .env /tmp/serverstatus-env-bak
[ -d data ] && mv data /tmp/serverstatus-data-bak
find . -mindepth 1 -maxdepth 1 -exec rm -rf {} +
ls -la
```

---

### 5.4 【服务器】第一把钥匙（拉 GitHub）

> 若以前部署过其它站，先测；成功则**整节跳过**，勿重复追加 `~/.ssh/config`。

```bash
ssh -T git@github.com
```

| 结果 | 下一步 |
|------|--------|
| `Hi topsnail!` | 跳到 5.5 |
| `Permission denied` 或显示仓库名 | 继续下面 |

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "vps-github-pull" -f ~/.ssh/vps_github -N ""
cat ~/.ssh/vps_github.pub
```

【GitHub 网页】https://github.com/settings/keys → **新建 SSH 密钥** → 粘贴公钥。

仅当 config 里还没有 `Host github.com` 时：

```bash
grep -q 'Host github.com' ~/.ssh/config 2>/dev/null || cat >> ~/.ssh/config << 'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/vps_github
  IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config ~/.ssh/vps_github
ssh -T git@github.com
```

**成功**：`Hi topsnail!`

---

### 5.5 【服务器】克隆代码

```bash
cd /apps/serverstatus
git clone git@github.com:topsnail/ServerStatus.git .
git checkout master
ls package.json Dockerfile.server deploy/docker-compose.yml scripts/deploy.sh
```

**成功**：尤其能看到 `deploy/docker-compose.yml` 与 `scripts/deploy.sh`。  
**缺 deploy/** → 回 **5.0** 先 push。

挪走过则移回：

```bash
[ -f /tmp/serverstatus-env-bak ] && mv /tmp/serverstatus-env-bak .env
[ -d /tmp/serverstatus-data-bak ] && mv /tmp/serverstatus-data-bak data
mkdir -p data backups
```

---

### 5.6 【服务器】配置 `.env` 与 `data/config.json`

```bash
cd /apps/serverstatus
cp deploy/env.example .env
mkdir -p data
[ -f data/config.json ] || cp server/config.json data/config.json
# 若误建成目录：rm -rf data/config.json && cp server/config.json data/config.json
openssl rand -hex 32
```

```bash
nano /apps/serverstatus/.env
```

```env
ADMIN_TOKEN=粘贴openssl生成的那一串
TZ=Asia/Shanghai
INSECURE_CALLBACK_TLS=false
VERBOSE=false
```

```bash
chmod 600 /apps/serverstatus/.env
ls -la data/config.json
```

**成功**：`ls` 显示普通文件（`-rw`），不是目录（`d`）。  
首次可不改 `data/config.json`；默认节点 `s01` / 密码 `USER_DEFAULT_PASSWORD`。

---

### 5.7 【服务器】构建并启动

首次（刚 clone，不必再 pull）：

```bash
cd /apps/serverstatus
chmod +x scripts/deploy.sh scripts/backup.sh
DEPLOY_SKIP_GIT=1 ./scripts/deploy.sh
```

以后日常：`./scripts/deploy.sh`

**成功**：输出 `Deploy OK`；`curl -s http://127.0.0.1:8080/api/health` 有 JSON。  
**失败时**：`docker logs --tail 100 serverstatus-server`；权限问题回 5.1；config 是目录按 5.6 处理。

---

### 5.8 【1Panel 网页】确认反向代理

确认目标为：

```text
http://127.0.0.1:8080
```

**成功**：`https://s.joanan.cn/` 出监控首页。  
仍 502：先在服务器 `curl -s http://127.0.0.1:8080/api/health`。

---

### 5.9 【浏览器】验收

| 检查 | 期望 |
|------|------|
| `https://s.joanan.cn/` | 首页正常 |
| `https://s.joanan.cn/api/health` | 200 JSON |
| WebUI「配置」 | 填入 `.env` 的 `ADMIN_TOKEN` 后能保存 |

```bash
curl -I https://s.joanan.cn/api/health
```

---

### 5.10 【被监控机器】安装客户端（可稍后）

⚠️ **`SERVER` 填法（最易错）：**

- ✅ `s.joanan.cn` 或公网 IP  
- ❌ 不要 `https://s.joanan.cn`（Agent 走 **TCP 35601**，不是网页）

```bash
docker run -d --restart=always --name=serverstatus-client \
  --network=host --pid=host \
  -e SERVER=s.joanan.cn \
  -e USER=s01 \
  -e PASSWORD=USER_DEFAULT_PASSWORD \
  cppla/serverstatus:client
```

**成功**：面板对应节点在线。失败则查 `35601`、用户名密码、`SERVER` 是否带了 `https://`。

---

## 6. 环境变量

改完后：

```bash
docker compose --project-directory . -f deploy/docker-compose.yml up -d
```

| 变量 | 说明 |
|------|------|
| `ADMIN_TOKEN` | 管理 Token；空则管理接口 503 |
| `TZ` | 默认 `Asia/Shanghai` |
| `INSECURE_CALLBACK_TLS` | 默认 `false` |
| `VERBOSE` | 默认 `false` |

| 项 | 值 |
|----|-----|
| HTTP 映射 | `127.0.0.1:8080:80` |
| Agent 映射 | `35601:35601` |
| 配置文件 | 宿主机 `data/config.json` |

---

## 7. GitHub 自动部署

**前提**：第 5 节完成，`https://s.joanan.cn` 能打开。  
第二把钥匙若桌面已有 `vps_deploy`，**直接复用**。

### 7.1 【你的电脑】

```powershell
cd $HOME\Desktop
ssh-keygen -t ed25519 -C "vps-github-actions" -f vps_deploy -N '""'
Get-Content .\vps_deploy.pub
```

### 7.2 【服务器】把公钥写入 `authorized_keys`

```bash
whoami
nano ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

本机测试（用户名改成 `whoami` 结果）：

```powershell
ssh -i $HOME\Desktop\vps_deploy -o IdentitiesOnly=yes root@你的服务器IP
```

### 7.3 【GitHub 网页】仓库机密

https://github.com/topsnail/ServerStatus/settings/secrets/actions

| 机密名 | 填什么 |
|--------|--------|
| `DEPLOY_HOST` | 服务器公网 IP |
| `DEPLOY_USER` | `whoami` 用户 |
| `DEPLOY_SSH_KEY` | 私钥 `vps_deploy` 全文 |
| `DEPLOY_APP_DIR` | `/apps/serverstatus` |
| `DEPLOY_PORT` | 可省略（默认 22） |

### 7.4 【服务器】试跑

```bash
cd /apps/serverstatus
./scripts/deploy.sh
```

### 7.5 触发

- `git push` 到 `master`（**只改 `.md` / LICENSE 不会触发**，这是故意的）  
- 或「操作」→ **Deploy** → **运行工作流**（改完机密后建议先手动跑一次验证）

**看日志时：**

- 绿色勾且日志有 `Deploy OK` / `workflow done` → 成功  
- 红色但其实服务器已更新 → 旧版曾开 `script_stop` 易误报；当前工作流已按 `1.yml` 去掉  
- SSH 连不上 → 回 7.2/7.3 查密钥与 `DEPLOY_HOST` / `DEPLOY_USER`

---

## 8. 备份与恢复及更换服务器

### 8.1 备份

```bash
cd /apps/serverstatus
bash scripts/backup.sh
```

更稳妥：先 `docker compose --project-directory . -f deploy/docker-compose.yml stop`，备份后再 `start`。

### 8.2 恢复

```bash
cd /apps/serverstatus
docker compose --project-directory . -f deploy/docker-compose.yml stop
rm -rf /tmp/ss-restore && mkdir -p /tmp/ss-restore
tar -xzf backups/serverstatus-YYYYMMDD-HHMMSS.tar.gz -C /tmp/ss-restore
cp -a /tmp/ss-restore/.env /apps/serverstatus/.env
cp -a /tmp/ss-restore/data/. /apps/serverstatus/data/
chmod 600 .env
docker compose --project-directory . -f deploy/docker-compose.yml up -d
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/api/health
```

### 8.3 换机

备份 → 新机 5.1 → clone → 恢复 `.env`/`data/` → `DEPLOY_SKIP_GIT=1 ./scripts/deploy.sh` → 1Panel 配 `s.joanan.cn` → 更新 `DEPLOY_HOST`。

---

## 9. 常见问题

| 现象 | 处理 |
|------|------|
| 网站 502 | 先 `curl http://127.0.0.1:8080/api/health`；通了再查反代 |
| 证书失败 | `s.joanan.cn` A 记录或 80 端口 |
| 克隆无 `deploy/` | 本机未 push → 5.0 |
| `docker: permission denied` | 5.1 加 docker 组并重登 |
| `data/config.json` 是目录 | `rm -rf` 后重新 `cp` 再启动 |
| 配置页 / API 503 | 设置 `ADMIN_TOKEN` 后重启容器 |
| 客户端不上线 | `SERVER` 不要带 `https://`；查 `35601` |
| 自动部署 SSH 失败 | 本机 `ssh -i` 自测；核对机密 |

---

## 附录：命令速查

```bash
cd /apps/serverstatus
DEPLOY_SKIP_GIT=1 ./scripts/deploy.sh   # 首次
./scripts/deploy.sh                     # 日常
docker compose --project-directory . -f deploy/docker-compose.yml ps
docker compose --project-directory . -f deploy/docker-compose.yml logs -f --tail=100
curl -s http://127.0.0.1:8080/api/health
curl -I https://s.joanan.cn/api/health
bash scripts/backup.sh
```

| 地址 | 说明 |
|------|------|
| `https://s.joanan.cn/` | WebUI |
| `https://s.joanan.cn/api/health` | 健康检查 |
| `s.joanan.cn:35601/tcp` | Agent 上报（不要用 https） |
