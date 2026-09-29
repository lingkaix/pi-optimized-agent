# pi-optimized-agent

Pi Coding Agent 的可安装配置骨架：packages、MCP、extensions、浏览器栈约定，以及幂等 `install.sh`。

## 定案摘要

- **浏览器栈**：日常交互用 Vercel `agent-browser`（CLI 步进）；重型 E2E 用 Playwright；二者共用 Playwright 安装的 Chrome for Testing，不重复下载。暂缓 Browser Use Pi（日常步进够用时再加）。
- **packages**：`context-mode`、`@ff-labs/pi-fff`、`@jamiefutch/pi-timeout`、`pi-tool-repair`、`pi-web-access`。
- **检索**：默认保持 Pi 四个核心工具；代码/路径检索走 `ffgrep`/`fffind`，大输出进 context-mode。
- **超时**：`runTimeout { maxSeconds: 30, fallbackMaxSeconds: 300 }`，与 pi-timeout 互补。
- **安全**：模板不含 API key；鉴权用目标机自己的登录。

## 目录

```
├── package.json
├── install.sh
├── README.md
├── AGENTS.md.template
├── scripts/merge-json.js
├── extensions/pi-tool-repair.json
└── prompts/README.md
```

## 安装

```bash
git clone https://github.com/lingkaix/pi-optimized-agent.git
cd pi-optimized-agent
chmod +x install.sh
./install.sh --check
./install.sh
./install.sh --with-agents   # 可选：写入 ~/.pi/agent/AGENTS.md（已存在则跳过）
```

安装内容（幂等，不覆盖你已有的同名配置项）：

1. `pi install` 五个 packages，并 merge `settings.json`（packages + runTimeout）
2. merge `mcp.json`（context-mode；优先写绝对 bin 路径）
3. 缺失时复制 `extensions/pi-tool-repair.json`
4. 检测或安装 Playwright Chromium，写入 `AGENT_BROWSER_EXECUTABLE_PATH`（`~/.pi/agent/browser.env`、已有的 `~/.bashrc` / `~/.zshrc`、`~/.agent-browser.json`）

也可用 `npm run check` / `npm run install`。

## 自检命令

```bash
source ~/.pi/agent/browser.env
agent-browser open https://example.com
agent-browser get title
agent-browser close --all

cd ~/.local/share/pi-browser-stack
node -e "const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();const p=await b.newPage();await p.goto('https://example.com');console.log(await p.title());await b.close()})()"
```

## 适配说明

- Chromium：`install.sh` 跨平台探测（Linux `chrome-linux*/chrome`；macOS `Google Chrome for Testing.app` 或旧版 `Chromium.app`，含 `~/Library/Caches/ms-playwright`）。也可预设 `AGENT_BROWSER_EXECUTABLE_PATH`。
- 模型 / provider 不在本包内，由目标机自行配置。
