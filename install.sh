#!/usr/bin/env bash
# install.sh — Pi Agent 优化配置 meta 包安装
# 幂等：可重复执行；只补缺失项，不覆盖用户已有配置；不写入任何 API key。
#
# 用法:
#   ./install.sh                  安装（pi packages + merge settings/mcp/extensions + 浏览器栈）
#   ./install.sh --check          只检查并报告目标机现状，不修改
#   ./install.sh --with-agents    额外把薄版 AGENTS.md 模板复制为 ~/.pi/agent/AGENTS.md
#   ./install.sh --skip-browser   跳过 Playwright Chromium / agent-browser 安装
set -euo pipefail

PI_DIR="${PI_CONFIG_DIR:-$HOME/.pi/agent}"
TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_ONLY=0
WITH_AGENTS=0
SKIP_BROWSER=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --with-agents) WITH_AGENTS=1 ;;
    --skip-browser) SKIP_BROWSER=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

PACKAGES=(
  "npm:context-mode"
  "npm:@ff-labs/pi-fff"
  "npm:@jamiefutch/pi-timeout"
  "npm:pi-tool-repair"
  "npm:pi-web-access"
)

echo "== pi-optimized-agent install =="
echo "  PI_DIR : $PI_DIR"
echo "  OS     : $(uname -s)-$(uname -m)"
echo "  MODE   : $([ "$CHECK_ONLY" = 1 ] && echo check || echo install)"

# --- 1. 环境检查 -----------------------------------------------------------
command -v node >/dev/null || { echo "FAIL: node 未安装（Pi 环境应自带）"; exit 1; }
command -v npm  >/dev/null || { echo "FAIL: npm 未安装"; exit 1; }
command -v pi   >/dev/null || { echo "FAIL: pi 未在 PATH 中"; exit 1; }

mkdir -p "$PI_DIR"
mkdir -p "$PI_DIR/extensions"

# --- 2. 通过 pi install 装 packages（幂等：已在 settings 则跳过） ----------
echo "[1/5] pi packages"
if [ "$CHECK_ONLY" = 1 ]; then
  if [ -f "$PI_DIR/settings.json" ]; then
    node -e '
      const fs=require("fs");
      const t=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
      const want=process.argv.slice(2);
      const miss=want.filter(p=>!(t.packages||[]).includes(p));
      console.log(miss.length?`  MISSING packages: ${miss.join(", ")}`:"  packages OK");
    ' "$PI_DIR/settings.json" "${PACKAGES[@]}"
  else
    echo "  MISSING settings.json / packages"
  fi
else
  for pkg in "${PACKAGES[@]}"; do
    if [ -f "$PI_DIR/settings.json" ] && grep -qF "\"$pkg\"" "$PI_DIR/settings.json" 2>/dev/null; then
      echo "  = $pkg (already listed)"
    else
      echo "  + pi install $pkg"
      # --no-approve: 全局包，不碰 project-local trust 提示
      if ! pi install "$pkg" --no-approve; then
        echo "  WARN: pi install $pkg failed — will still merge into settings.json"
      fi
    fi
  done
fi

# --- 3. settings.json：packages + runTimeout（双保险 merge） ---------------
echo "[2/5] settings.json (packages + runTimeout)"
cat > "$TOOL_DIR/.settings.patch.json" <<'JSON'
{
  "packages": [
    "npm:context-mode",
    "npm:@ff-labs/pi-fff",
    "npm:@jamiefutch/pi-timeout",
    "npm:pi-tool-repair",
    "npm:pi-web-access"
  ],
  "runTimeout": { "maxSeconds": 30, "fallbackMaxSeconds": 300 }
}
JSON
if [ "$CHECK_ONLY" = 1 ]; then
  if [ -f "$PI_DIR/settings.json" ]; then
    node -e '
      const fs=require("fs");
      const t=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
      const rt=t.runTimeout;
      console.log(rt&&rt.maxSeconds?"  runTimeout OK":"  MISSING runTimeout");
    ' "$PI_DIR/settings.json"
  fi
else
  if [ ! -f "$PI_DIR/settings.json" ]; then echo '{}' > "$PI_DIR/settings.json"; fi
  node "$TOOL_DIR/scripts/merge-json.js" "$PI_DIR/settings.json" "$TOOL_DIR/.settings.patch.json"
fi
rm -f "$TOOL_DIR/.settings.patch.json"

# --- 4. mcp.json：context-mode + codegraph（原生 MCP） -----------------------
echo "[3/5] mcp.json (context-mode + codegraph)"
# Prefer absolute bin under Pi's package tree so MCP works without global PATH
CM_BIN="$PI_DIR/npm/node_modules/.bin/context-mode"
if [ -x "$CM_BIN" ]; then
  cat > "$TOOL_DIR/.mcp.patch.json" <<JSON
{
  "mcpServers": {
    "context-mode": { "command": "$CM_BIN" },
    "codegraph": {
      "command": "codegraph",
      "args": ["serve", "--mcp"],
      "exposure": "direct"
    }
  }
}
JSON
else
  cat > "$TOOL_DIR/.mcp.patch.json" <<'JSON'
{
  "mcpServers": {
    "context-mode": { "command": "context-mode" },
    "codegraph": {
      "command": "codegraph",
      "args": ["serve", "--mcp"],
      "exposure": "direct"
    }
  }
}
JSON
fi
if [ "$CHECK_ONLY" = 1 ]; then
  node -e '
    const fs=require("fs");
    let cm=false, cg=false;
    try {
      const t=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
      cm=!!(t.mcpServers&&t.mcpServers["context-mode"]);
      cg=!!(t.mcpServers&&t.mcpServers["codegraph"]);
    } catch {}
    console.log(cm?"  context-mode MCP OK":"  MISSING context-mode MCP");
    console.log(cg?"  codegraph MCP OK":"  MISSING codegraph MCP");
  ' "$PI_DIR/mcp.json"
else
  if [ ! -f "$PI_DIR/mcp.json" ]; then echo '{}' > "$PI_DIR/mcp.json"; fi
  node "$TOOL_DIR/scripts/merge-json.js" "$PI_DIR/mcp.json" "$TOOL_DIR/.mcp.patch.json"
  # If context-mode already existed as bare "context-mode", upgrade to absolute bin
  CM_BIN="$PI_DIR/npm/node_modules/.bin/context-mode"
  if [ -x "$CM_BIN" ] && [ -f "$PI_DIR/mcp.json" ]; then
    node -e '
      const fs=require("fs");
      const f=process.argv[1], bin=process.argv[2];
      const j=JSON.parse(fs.readFileSync(f,"utf8"));
      const cur=j.mcpServers&&j.mcpServers["context-mode"];
      if(cur && cur.command==="context-mode"){
        cur.command=bin; fs.writeFileSync(f, JSON.stringify(j,null,2)+"\n");
        console.log("  ~ mcpServers.context-mode.command -> absolute");
      }
    ' "$PI_DIR/mcp.json" "$CM_BIN"
  fi
fi
rm -f "$TOOL_DIR/.mcp.patch.json"

# --- 5. extensions/pi-tool-repair.json --------------------------------------
echo "[4/5] pi-tool-repair.json (grammarRepair)"
if [ -f "$PI_DIR/extensions/pi-tool-repair.json" ]; then
  echo "  exists — 保留用户已有配置"
else
  if [ "$CHECK_ONLY" = 1 ]; then
    echo "  MISSING pi-tool-repair.json"
  else
    cp "$TOOL_DIR/extensions/pi-tool-repair.json" "$PI_DIR/extensions/pi-tool-repair.json"
    echo "  + installed"
  fi
fi

# --- 6. 浏览器栈：chromium 检测 / 安装 / env -------------------------------
echo "[5/5] browser stack"
find_chromium() {
  local cand base
  if [ -n "${AGENT_BROWSER_EXECUTABLE_PATH:-}" ] && [ -x "$AGENT_BROWSER_EXECUTABLE_PATH" ]; then
    echo "$AGENT_BROWSER_EXECUTABLE_PATH"
    return 0
  fi
  # Prefer find over fragile globs (macOS app name: "Google Chrome for Testing")
  for base in \
    "$HOME/Library/Caches/ms-playwright" \
    "$HOME/.cache/ms-playwright"; do
    [ -d "$base" ] || continue
    # Linux chrome binary
    while IFS= read -r cand; do
      [ -x "$cand" ] && { echo "$cand"; return 0; }
    done < <(find "$base" -type f \( -path "*/chrome-linux*/chrome" -o -path "*/chrome-linux/chrome" \) 2>/dev/null | head -5)
    # macOS: Google Chrome for Testing (current) or Chromium.app (legacy)
    while IFS= read -r cand; do
      [ -x "$cand" ] && { echo "$cand"; return 0; }
    done < <(find "$base" -type f \( \
      -path "*/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing" \
      -o -path "*/Chromium.app/Contents/MacOS/Chromium" \
    \) 2>/dev/null | head -5)
  done
  return 1
}

ensure_shell_export() {
  # 幂等写入 bashrc / zshrc（Mac 默认 zsh）
  local chromium="$1"
  local rc
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ ! -f "$rc" ]; then
      # 仅在常见 rc 已存在时追加；不主动新建空的 .bashrc 干扰
      continue
    fi
    if grep -q "AGENT_BROWSER_EXECUTABLE_PATH" "$rc" 2>/dev/null; then
      echo "  $rc OK"
    else
      {
        echo ""
        echo "# pi-optimized-agent: shared Playwright Chromium for agent-browser"
        echo "export AGENT_BROWSER_EXECUTABLE_PATH=\"$chromium\""
      } >> "$rc"
      echo "  + $rc export"
    fi
  done
  # 若两者都不存在（极少见），写一份 .zshrc
  if [ ! -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.zshrc" ]; then
    echo "export AGENT_BROWSER_EXECUTABLE_PATH=\"$chromium\"" > "$HOME/.zshrc"
    echo "  + ~/.zshrc (created)"
  fi
}

CHROMIUM=""
CHROMIUM="$(find_chromium || true)"

if [ "$SKIP_BROWSER" = 1 ]; then
  echo "  skipped (--skip-browser)"
elif [ "$CHECK_ONLY" = 1 ]; then
  if [ -n "$CHROMIUM" ]; then
    echo "  chromium : $CHROMIUM"
  else
    echo "  MISSING Playwright Chromium"
  fi
  command -v agent-browser >/dev/null && echo "  agent-browser OK ($(agent-browser --version 2>/dev/null || echo present))" || echo "  MISSING agent-browser"
  grep -q AGENT_BROWSER_EXECUTABLE_PATH "$PI_DIR/browser.env" 2>/dev/null && echo "  browser.env OK" || echo "  MISSING browser.env"
  [ -f "$HOME/.agent-browser.json" ] && echo "  ~/.agent-browser.json OK" || echo "  MISSING ~/.agent-browser.json"
else
  # agent-browser CLI
  if ! command -v agent-browser >/dev/null; then
    echo "  + npm i -g agent-browser"
    npm install -g agent-browser
  else
    echo "  agent-browser OK ($(agent-browser --version 2>/dev/null || echo present))"
  fi

  # Playwright Chromium
  if [ -z "$CHROMIUM" ] || [ ! -x "$CHROMIUM" ]; then
    echo "  + installing Playwright Chromium (npx playwright install chromium)"
    # 独立目录，避免污染全局；浏览器二进制仍落到默认 cache
    local_pw="$HOME/.local/share/pi-browser-stack"
    mkdir -p "$local_pw"
    if [ ! -f "$local_pw/package.json" ]; then
      (cd "$local_pw" && npm init -y >/dev/null 2>&1 && npm install playwright@1 --no-fund --no-audit)
    elif [ ! -d "$local_pw/node_modules/playwright" ]; then
      (cd "$local_pw" && npm install playwright@1 --no-fund --no-audit)
    fi
    (cd "$local_pw" && npx playwright install chromium)
    CHROMIUM="$(find_chromium || true)"
  fi

  if [ -n "$CHROMIUM" ] && [ -x "$CHROMIUM" ]; then
    echo "  chromium : $CHROMIUM"
    # 路径含空格（macOS "Google Chrome for Testing"），必须带引号以便 source
    # 用 printf 写文件，避免 echo 吞引号的坑
    current=""
    if [ -f "$PI_DIR/browser.env" ]; then
      current="$(grep '^AGENT_BROWSER_EXECUTABLE_PATH=' "$PI_DIR/browser.env" | tail -1 || true)"
    fi
    desired_val="$CHROMIUM"
    # 期望行：AGENT_BROWSER_EXECUTABLE_PATH="..."
    if [ "$current" = "AGENT_BROWSER_EXECUTABLE_PATH=\"$desired_val\"" ]; then
      echo "  browser.env OK"
    else
      tmp="$(mktemp)"
      if [ -f "$PI_DIR/browser.env" ]; then
        grep -v '^AGENT_BROWSER_EXECUTABLE_PATH=' "$PI_DIR/browser.env" > "$tmp" || true
      else
        : > "$tmp"
      fi
      printf 'AGENT_BROWSER_EXECUTABLE_PATH="%s"\n' "$CHROMIUM" >> "$tmp"
      mv "$tmp" "$PI_DIR/browser.env"
      echo "  + browser.env"
    fi
    if [ ! -f "$HOME/.agent-browser.json" ] || ! grep -q "\"executablePath\"" "$HOME/.agent-browser.json" 2>/dev/null; then
      printf '{\n  "executablePath": "%s"\n}\n' "$CHROMIUM" > "$HOME/.agent-browser.json"
      echo "  + ~/.agent-browser.json"
    else
      echo "  ~/.agent-browser.json OK"
    fi
    mkdir -p "$HOME/.config/agent-browser"
    if [ ! -f "$HOME/.config/agent-browser/config.json" ]; then
      printf '{\n  "executablePath": "%s"\n}\n' "$CHROMIUM" > "$HOME/.config/agent-browser/config.json"
      echo "  + ~/.config/agent-browser/config.json"
    fi
    ensure_shell_export "$CHROMIUM"
  else
    echo "  WARN: 仍未找到 Playwright Chromium。"
    echo "        手动: cd ~/.local/share/pi-browser-stack && npx playwright install chromium"
  fi
fi

# --- 7. AGENTS.md 模板（可选） ---------------------------------------------
if [ "$WITH_AGENTS" = 1 ]; then
  echo "[optional] AGENTS.md 模板"
  if [ -f "$PI_DIR/AGENTS.md" ]; then
    echo "  ~/.pi/agent/AGENTS.md 已存在 — 跳过（不覆盖用户内容）"
  else
    if [ "$CHECK_ONLY" = 1 ]; then
      echo "  MISSING AGENTS.md"
    else
      cp "$TOOL_DIR/AGENTS.md.template" "$PI_DIR/AGENTS.md"
      echo "  + AGENTS.md"
    fi
  fi
fi

echo ""
echo "== 完成 =="
if [ -n "${CHROMIUM:-}" ]; then
  echo "冒烟（agent-browser）:"
  echo "  export AGENT_BROWSER_EXECUTABLE_PATH=\"$CHROMIUM\""
  echo "  agent-browser open https://example.com && agent-browser get title && agent-browser close --all"
fi
echo "冒烟（Playwright）:"
echo "  cd ~/.local/share/pi-browser-stack && node -e \"const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();const p=await b.newPage();await p.goto('https://example.com');console.log(await p.title());await b.close()})()\""
echo "详见 README.md"
