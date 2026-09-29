# Smoke results

## Linux box (2026-09-29)
- agent-browser → Example Domain — PASS
- Playwright chromium.launch → Example Domain — PASS

## macOS arm64 M5Pros-MBP (2026-09-29, meta 0.1.5)
- `./install.sh` — packages / runTimeout / mcp absolute context-mode / grammarRepair / Chromium detect — PASS
- `browser.env` quoted path `source` — PASS
- agent-browser open https://example.com → title Example Domain — PASS
- Playwright at `~/.local/share/pi-browser-stack` → title Example Domain — PASS
- second `./install.sh` idempotent — PASS

Chromium (mac):
`/Users/m5pro/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing`
