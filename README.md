# Claude Code 多角色信箱工作流 Template

持久多角色 session + git-doc 信箱 relay + hook 主動喚醒的協作工作流。從 [ivanlin630/demo](https://github.com/ivanlin630/demo)（Godot 世界模擬器）萃取。

## 核心概念

多個持久 `claude` session 各扮一角色（藍圖/系統/實作/QA/審查/量測員），透過 **git 資料夾當共享信箱**（`docs/superpowers/handbacks/`）互傳 handback。hook 讓收件方 **~20s 內主動被喚醒**，不需人肉轉述 → 跨角色工作 **自動鏈**，只在需人裁決時停。

**真正有價值的三件核心（作者實測）：**
1. **對抗角色分離**——maker 不驗自己作業。獨立量測/審查抓自檢盲點。
2. **measure-first**——先量再下結論；單 seed≠真，靠 full_probe + 多 seed 破假設。
3. **信箱自動鏈**——長串跨角色流程自動跑，人只在 sign-off 插手。

**較弱/可選：** LG orchestrator（`tools/orchestrator/`，$成本高、少用）、定時器（CronCreate session-only）。

## 結構

| 路徑 | 作用 | 可攜性 |
|---|---|---|
| `.claude/hooks/inbox-watch.sh` | 信箱監看→主動喚醒（Monitor 用） | 純機制，git 路徑動態推導、**免改** |
| `.claude/hooks/handback-inbox.sh` | UserPromptSubmit 掃未讀信 | 純機制、**免改** |
| `.claude/hooks/session-role.sh` | SessionStart 依 `$SESSION_ROLE` 注入角色 context | ★**要改**：CTX 字串含來源專案味（godot 等） |
| `.claude/hooks/layer-check.sh` / `implementer-cleanup.sh` | Edit 護欄 / Stop 清理 | 視需求，可留可刪 |
| `.claude/settings.json` | hook 接線 + statusLine | 相對路徑、**免改** |
| `.claude/statusline-command.ps1` | **全域角色狀態列**：渲染 `[藍圖 WHAT]`/`[系統 HOW]`/`[QA]`/`[審查]`/`[實作]`/`[量測]` badge + ctx%/model/cwd/git | ★**Windows/PowerShell**；自足、免改（含可選 caveman badge，無 plugin 則 no-op） |
| `docs/process/00-08*.md` | 角色定義 / 邊界 / 流程正典 | ★**要改**：內容專案特定，結構可沿用 |
| `docs/superpowers/handbacks/` | 信箱資料夾 | 空模板 |
| `tools/orchestrator/*.py` | LG 機器軌（可選） | 需 langgraph；不用可刪 |

## 套用到新專案

1. **複製** `.claude/`、`docs/process/`、`docs/superpowers/handbacks/`（+ 選 `tools/orchestrator/`）進你的 repo。
2. **改** `session-role.sh` 各角色 CTX 字串 + `docs/process/*.md` → 換成你專案的指令/工具/邊界（現版是 Godot sim 味）。
3. **開角色 session**（各一終端）：
   ```
   # bash
   SESSION_ROLE=blueprint claude
   # PowerShell
   $env:SESSION_ROLE='blueprint'; claude
   ```
   角色：`blueprint`（WHAT）/`systems`（HOW）/`implementer`/`qa`/`reviewer`/`measurer`。
4. SessionStart hook 自動注入角色 + 指示開場 arm 常駐信箱 Monitor（`bash .claude/hooks/inbox-watch.sh`）。
5. 寄信 = Write 一個 handback md（frontmatter `from/to/status/topic`）到 handbacks/；收件角色 ~20s 內被喚醒。動完改 `status: consumed`。

## handback 信格式

```markdown
---
from: blueprint
to: systems
status: open        # open→收件方讀 / consumed→已處理
topic: 一句話主題
---

# 內文（決策/方向/數字/裁定）
```

## 誠實限制

- **「獨立」有水分**：角色都是同一個模型開不同 session，靠分 context + 對抗 prompt 造視角差，非真獨立。**人在迴圈做真活**——這套放大你的判斷，取代不了會戳假設的使用者。
- **重**：handback ceremony 多，overhead-to-output 比高。**長命複雜專案值得（盲點會複利），小活過度。**
- **hooks 需 bash**（Windows 用 git-bash）+ Claude Code 支援 SessionStart/UserPromptSubmit/PreToolUse/Stop hooks + Monitor 工具。
- LG 軌需 langgraph + 成本高，預設冷凍；純 mailbox 軌即可運作。

## 授權

從 ivanlin630/demo 萃取，供自用。
