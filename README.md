# pi-optimized-agent — Pi Agent 优化配置 meta 包

本机 Pi harness（0.87.1）优化配置的**可安装骨架**：packages 依赖、浏览器栈定案、超时策略、薄纪律层。设计为在新机器上一键复现。

> 背景与完整定案见知识库报告：`KnowledgeBase/reports/pi-agent-config/optimized-config.md`
> 冒烟记录：`SMOKE.md`（两路 PASS，2026-09-29）

## 定案摘要

- **浏览器栈**：日常交互 = Vercel agent-browser（CLI 步进式）；重型 E2E = Playwright；二者**共用 Playwright 的 Chrome for Testing 内核**（不重复下载）；**暂缓 Browser Use Pi**（CLI 步进已覆盖日常，长自主循环无刚需；历史 PASS 记录在 KB）。
- **packages**：`context-mode`（大输出闸门）、`@ff-labs/pi-fff`（ffgrep/fffind）、`@jamiefutch/pi-timeout`（bash 超时兜底）、`pi-tool-repair`（grammarRepair 假文本 tool call 恢复）、`pi-web-access`（零 key 网页搜索/抓取）。
- **超时**：`runTimeout { maxSeconds: 30, fallbackMaxSeconds: 300 }` + pi-timeout 自动注入，互补不互斥。
- **安全**：模板不含任何 API key；auth 走目标机自身登录。

## 目录结构

```
pi-meta-package/
├── package.json              Pi manifest（pi.packages / extensions / prompts 说明）
├── install.sh                安装骨架（幂等，--check / --with-agents）
├── README.md
├── SMOKE.md                  冒烟记录（两路 PASS）
├── AGENTS.md.template        薄纪律层（可选复制）
├── scripts/merge-json.js     幂等 JSON 合并（只补缺失）
├── extensions/pi-tool-repair.json
└── prompts/README.md         prompt 分层说明
```

## 安装

```bash
cd /workspace/pi-meta-package
chmod +x install.sh
./install.sh --check         # 先看目标机现状（不修改）
./install.sh                 # 安装：merge settings/mcp/extensions + 写浏览器 env
./install.sh --with-agents   # 可选：复制薄版 AGENTS.md 模板
```

安装做四件事（全部幂等，不覆盖用户已有配置）：

1. `settings.json` ← merge `packages`（5 个）+ `runTimeout`
2. `mcp.json` ← 确保 `context-mode` server
3. `extensions/pi-tool-repair.json` ← 缺失才复制
4. 浏览器栈 ← 检测/复用 Playwright Chromium，写 `AGENT_BROWSER_EXECUTABLE_PATH`（`~/.pi/agent/browser.env`、`~/.bashrc`、`~/.agent-browser.json`）；未找到则提示 `npx playwright install chromium`

> `npm run check` / `npm run install` 亦可（等价于上面两条）。

## 冒烟命令

agent-browser（日常）：

```bash
# 路径以 install 结束时打印的为准，或 source ~/.pi/agent/browser.env
source ~/.pi/agent/browser.env   # 或 export AGENT_BROWSER_EXECUTABLE_PATH=...
agent-browser open https://example.com
agent-browser get title        # → Example Domain
agent-browser snapshot -i
agent-browser close --all
```

Playwright（重型，在 `/home/box/.local/share/pi-browser-stack` 内）：

```bash
node -e "const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();const p=await b.newPage();await p.goto('https://example.com');console.log(await p.title());await b.close()})()"
# → Example Domain
```

## 新机适配点

- Chromium：`install.sh` 用 `find` 跨平台探测（Linux `chrome-linux*/chrome`；macOS `Google Chrome for Testing.app` / 旧版 `Chromium.app`，含 `~/Library/Caches/ms-playwright`）；缺失时自动安装。也可预设 `AGENT_BROWSER_EXECUTABLE_PATH`。
- Packages：通过 `pi install` 真正装扩展，再 merge `settings.json` / `mcp.json`（幂等）。
- Shell：同时幂等写入已存在的 `~/.bashrc` 与 `~/.zshrc`。
- 模型 / provider：不在本包内（目标机自定）。
- 知识库路径：本 box 特有，新机按需跳过。
