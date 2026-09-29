# prompts / 分层说明

原则：**能用扩展/settings 强制的，不写进 AGENTS.md**；prompt 只留扩展盖不住的短纪律。

| 层 | 载体 | 内容 |
|----|------|------|
| 声明式配置 | `settings.json`（packages / runTimeout）、`mcp.json`、`extensions/pi-tool-repair.json` | 由 install.sh 合并，无需提示词 |
| 薄纪律层 | `AGENTS.md.template`（可选 `--with-agents` 复制为 `~/.pi/agent/AGENTS.md`） | 搜索顺序、禁文本 invoke、浏览器栈指针 |
| 项目级 | 各仓库自身 `AGENTS.md` | 项目专属纪律，不入本包 |

不在模板里写：API key / auth（目标机各自登录）、模型名（可改）、情绪化措辞。
