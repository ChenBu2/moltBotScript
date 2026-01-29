# Moltbot 一键部署与启动指南

本指南说明如何使用跨平台一键脚本在 Linux、macOS 与 Windows 上部署并启动 Moltbot Gateway。脚本已适配原生与 Docker 两种模式，自动处理 Node≥22、Corepack/pnpm、依赖安装与日志输出。

Moltbot地址：https://github.com/moltbot/moltbot

## 文件清单

- Linux/macOS 脚本：[`scripts/moltbot.sh`](scripts/moltbot.sh)
- Windows 脚本：[`scripts/moltbot.ps1`](scripts/moltbot.ps1)

## 适用平台与前提条件

- Node.js 版本需 ≥ 22；脚本会自动尝试安装/切换到 22。
- 包管理：优先启用 Corepack 并激活 pnpm；若不可用则回退 npm 全局安装 pnpm。
- Docker（可选）：如使用 Docker 模式需预装 Docker 与 docker compose。
- 推荐 Windows 使用 WSL2 获得更接近 Linux 的体验（官方文档建议）。

## 快速开始

### Linux/macOS（原生模式）

```bash
bash scripts/moltbot.sh
```

指定 Docker 模式：

```bash
bash scripts/moltbot.sh --mode docker
```

指定渠道与端口：

```bash
bash scripts/moltbot.sh --channel beta --port 18789
```

环境变量覆盖：

```bash
MODE=docker CHANNEL=dev PORT=18789 bash scripts/moltbot.sh
```

### Windows（PowerShell 7+）

```powershell
.\scripts\moltbot.ps1 -Mode native -Channel stable -Port 18789
```

从源码仓库运行：

```powershell
.\scripts\moltbot.ps1 -Mode native
```

Docker 模式：

```powershell
.\scripts\moltbot.ps1 -Mode docker
```

环境变量覆盖：

```powershell
$env:MODE='docker'; $env:CHANNEL='beta'; $env:PORT='18789'; .\scripts\moltbot.ps1
```

## 运行路径判定

- 仓库根目录（检测 `package.json` + `pnpm-workspace.yaml`）：执行源码安装 → 构建 → 以开发模式启动（自动重载）。
  - 安装：`pnpm install`
  - UI 构建（首次会自动安装 UI 依赖）：`pnpm ui:build`（失败不阻断）
  - 项目构建：`pnpm build`
  - 启动：`pnpm gateway:watch`
- 非仓库目录（全局安装）：全局安装 moltbot@stable|beta|dev → 运行向导安装守护进程 → 启动 Gateway。
  - 启动命令：`moltbot gateway --port 18789 --verbose`

## 模式说明

- 原生模式（默认）：在当前主机上安装并运行 Gateway。
- Docker 模式：使用仓库的 Docker 配置启动服务；优先 `docker compose up -d`，回退 `docker-compose up -d`。

## 参数与环境变量

- `--mode`：`native|docker`，默认 `native`。
- `--channel`：`stable|beta|dev`，默认 `stable`（仅全局安装路径生效）。
- `--port`：默认 `18789`。
- 环境变量覆盖：`MODE`、`CHANNEL`、`PORT`。
- `.env` 支持：脚本在仓库根目录读取 `.env` 并注入当前进程环境。

## 日志与健康检查

- Linux/macOS：日志写入 `/tmp/moltbot-gateway.log`。
- Windows：日志写入 `%TEMP%\moltbot-gateway.log`。
- 查看健康状态与风险配置：`moltbot doctor`。
- 常用发送示例：`moltbot message send --to +1234567890 --message "Hello from Moltbot"`。

## 自动安装与版本管理

- macOS：优先使用 Homebrew 安装 `node@22`，失败回退到 nvm 安装。
- Linux：优先使用 `apt/dnf/yum` 与 NodeSource 安装 node 22，失败回退到 nvm。
- Windows：优先使用 winget 安装 Node（OpenJS.NodeJS）；失败则安装 NVM for Windows 并切换到 22。
- 包管理：启用 Corepack 并激活 pnpm；若不可用则以 npm 全局安装 pnpm。

## Windows 注意事项

- 首次运行 PowerShell 脚本可能需要管理员执行：`Set-ExecutionPolicy RemoteSigned`。
- 如需更好兼容性，建议在 WSL2 中使用 Linux 路径运行脚本。
- 当 `docker-setup.sh` 存在且系统有 bash 时，脚本会尝试执行以完成仓库内 Docker 初始化。

## 故障排查

- Node 版本不足或安装失败：检查网络、镜像源或手动安装 Node≥22；Windows 可确认 NVM 安装成功并执行 `nvm use 22`。
- pnpm/ Corepack 不可用：确保 npm 已安装；脚本会用 `npm i -g pnpm@latest` 回退安装。
- docker compose 不可用：确认 Docker Desktop 已安装并启用 compose 插件；或安装 `docker-compose` 二进制。
- 端口占用：修改 `--port` 参数或释放 18789。
- 权限问题：macOS 需要按需授权通知、屏幕录制等；Windows 注意执行策略。
- 网络/代理：若安装依赖超时，请配置企业代理或使用近源镜像。

## 安全建议（重要）

- 默认工具在主会话（main）上具有主机访问能力；如需在群组或非主会话中隔离执行，请参考官方的 Docker sandbox 配置与 allowlist/denylist。
- 在暴露 Control UI/WebChat 时务必遵循文档安全指引（例如 Tailscale Serve/Funnel 要求密码）。
- 不信任入站 DM，默认采用 pairing 模式；按需在各渠道配置 allowlist。
- 在 `.env` 与配置文件中保存的密钥请妥善管理，避免提交到版本库。

## 常见操作速查

- 更新到 beta/dev 渠道（全局安装）：运行脚本时带 `--channel beta|dev`。
- 安装守护进程：`moltbot onboard --install-daemon`。
- 停止/重启：根据平台使用系统服务管理或直接关闭进程后重启脚本。
- 查看日志：Linux/macOS 查看 `/tmp/moltbot-gateway.log`；Windows 查看 `%TEMP%\moltbot-gateway.log`。
- 从源码进入开发循环：`pnpm gateway:watch`。

## 维护与贡献

- 脚本版本号与时间戳已内置，修改请同步更新两端脚本。
- 如需扩展（例如加入 Tailscale/Funnel、远程网关、更多渠道预设），可在脚本中新增参数并在本说明补充使用方法。
- 欢迎对脚本与说明提出改进建议并提交 PR。

## 变更记录

- 2026-01-29：首次发布跨平台一键部署/启动脚本与说明文档。

——

如需追加 Windows Batch 版本以兼容更老环境，请告知，我将补充 [`scripts/moltbot.bat`](scripts/moltbot.bat) 与相应文档章节。