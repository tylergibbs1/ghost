# Ghost

**The last mile for AI agents on macOS. For the stuff bash can't reach.**

Swift. Native accessibility APIs. Instant.

Ghost reads the macOS accessibility tree and gives AI agents structured, token-efficient access to GUI-only apps. Actions target elements by name and role, not coordinates. Every action returns a diff of what changed. The agent never needs to "see" the screen.

```bash
ghost observe "System Settings"
```
```
[app] System Settings
  [window] System Settings
    [sidebar]
      [item] Wi-Fi (selected)
      [item] Network
    [content]
      [heading] Wi-Fi
      [toggle] Wi-Fi (on)
      [text] Connected to "HomeNetwork"
```

~80 tokens. Not ~3000 for a screenshot.

---

## Install

Requires macOS 13+ and Swift 5.9+. Build from source:

```bash
git clone https://github.com/tylergibbs1/ghost.git
cd ghost
swift build -c release
cp .build/release/ghost /usr/local/bin/
```

Grant accessibility permission when prompted (System Settings > Privacy & Security > Accessibility).

## Quick start

```bash
ghost observe                     # list running apps
ghost observe "System Settings"   # read one app's accessibility tree
ghost serve --mcp                 # expose Ghost to an agent as an MCP server
```

---

## What Ghost is not

- **Not a replacement for bash.** Enforced with an app blocklist.
- **Not a screenshot tool.** Never captures pixels.
- **Not a macro recorder.** Semantic actions, not coordinate clicks.
- **Not cross-platform (yet).** macOS first. Windows and Linux are future work.
- **Not universal.** Custom-drawn UIs and games are out of scope.

---

## Commands

### observe — Read the GUI

```bash
# List all running apps (~200 tokens)
ghost observe

# Read a specific app's accessibility tree
ghost observe "Finder"

# Focus on a subtree (saves tokens)
ghost observe "System Settings" --focus "content"

# JSON format with element IDs, actions, frames
ghost observe "Finder" --format detailed

# Control list truncation
ghost observe "Notes" --max-items 20
```

### interact — Do things

```bash
# Press a button
ghost interact "System Settings" press "About" --mode open

# Type into a field
ghost interact "System Settings" type "DNS Servers" --value "1.1.1.1" --mode open

# Select a sidebar item
ghost interact "System Settings" select "sidebar > Network" --mode open

# Send a keyboard shortcut
ghost interact "Keynote" key "menubar" --value "cmd+s" --mode open

# Navigate to an app
ghost interact desktop navigate "System Settings" --mode open

# Get the full tree back after the action
ghost interact "Notes" press "About Notes" --mode open --include-tree
```

Every interact call returns a structural diff:
```
Action: press [toggle] Wi-Fi
Result: success
Diff:
  [changed] content > toggle > Wi-Fi value: "on" -> "off"
  [removed] content > text > Connected to "HomeNetwork"
```

### explore — Map an entire app autonomously

Ghost Explore is an autonomous cartography engine. It systematically tries every action in every reachable state and builds a complete state graph of what an app can do.

```bash
# Map System Settings (depth 4, max 100 states, 2 min timeout)
ghost explore "System Settings" --max-depth 4 --max-states 100 --timeout 120

# Explore VS Code
ghost explore "Code" --max-depth 3 --timeout 60

# Include text fields and dangerous actions
ghost explore "Notes" --text-fields --dangerous
```

Output:
```
Exploring System Settings...
  [12 states, 847/2041 actions (41%)] System Settings > Network > DNS

Saved: ~/.ghost/maps/system-settings.ghostmap

App: System Settings
States: 12
Actions: 2041 (847 explored)
Transitions: 23
Max depth: 3
Duration: 118.4s

State graph:
[System Settings > Wi-Fi]  (156 actions, 4 nav, 3 toggles)
  press "Network" → stateChange
  press "Wi-Fi toggle" → valueToggle
  [System Settings > Network]  (89 actions, 2 nav, 1 toggles)
    press "DNS" → stateChange
    [System Settings > Network > DNS]  (34 actions, 0 nav, 0 toggles)
```

### query — Search an app's map

```bash
# Find how to reach a setting
ghost query "system-settings" "DNS"
# → [action] Network > DNS > add server (3 steps)
#   Path: → press "Network" → press "DNS" → press "Add"

# List every configurable parameter
ghost query "system-settings" --params
# → [toggle] Wi-Fi  via: Wi-Fi
# → [textfield] DNS Servers  via: Network > DNS
# → [dropdown] Security  via: Wi-Fi > network > Security
```

### snapshot — Track state changes

```bash
# Save state before a workflow
ghost snapshot "System Settings" capture "before-dns"

# Compare current state to snapshot
ghost snapshot "System Settings" compare "before-dns"

# Boolean check (for assertions)
ghost snapshot "System Settings" check "before-dns"
```

### serve — MCP server for agents

```bash
# Run as an MCP server (JSON-RPC 2.0 over stdio)
ghost serve --mcp

# With permission mode
ghost serve --mcp --mode open

# With visual overlay
ghost serve --mcp --overlay
```

Exposes three tools: `ghost_observe`, `ghost_interact`, `ghost_snapshot`.

### transport — Raw JSON mode

```bash
# stdin/stdout newline-delimited JSON
echo '{"command":"observe"}' | ghost transport
echo '{"command":"observe","app":"Finder","focus":"toolbar"}' | ghost transport
echo '{"command":"interact","app":"Notes","action":"press","target":"About Notes"}' | ghost transport
```

---

## Permission system

Ghost uses a Claude Code-inspired permission model. Read operations are always free. Write operations require permission.

### Modes

| Mode | Behavior |
|------|----------|
| `plan` | Read only. Agent sees the full tree but can't interact. |
| `default` | Prompts for each new action type. |
| `allowlist` | Only pre-approved actions work. |
| `open` | Everything allowed. For sandboxed environments only. |

### Rules

Rules use wildcard specifiers:
```json
{
  "permissions": {
    "allow": [
      "Observe",
      "Navigate",
      "Press(System Settings > content > *)",
      "Type(System Settings > content > *)"
    ],
    "deny": [
      "Press(* > * > Erase *)",
      "Press(* > * > Delete)",
      "Key(* cmd+q)"
    ]
  }
}
```

Deny always wins. Settings hierarchy: managed > user (`~/.ghost/settings.json`) > project (`.ghost/settings.json`).

### App blocklist

CLI apps return an error — use bash instead:
```bash
ghost observe "Terminal"
# Error: Terminal is a CLI application. Use bash instead.
```

Blocked: Terminal, iTerm2, Ghostty, Warp, Alacritty, Kitty, and others.

---

## Visual overlay

Ghost can show what the agent is doing on screen in real time. Transparent, click-through window with Core Animation highlights.

```bash
# Enable overlay for any command
ghost observe "Finder" --overlay
ghost interact "Notes" press "About Notes" --mode open --overlay

# Run the demo
ghost overlay-demo --duration 5 --speed normal

# With MCP server
ghost serve --mcp --overlay
```

Each action type has its own color and animation:

| Action | Color | Animation |
|--------|-------|-----------|
| observe | Gray | Subtle fade |
| press | System accent | Spring scale + ripple |
| type | Green | Cursor blink on border |
| select | Purple | Fade |
| key | Orange | Shortcut HUD |
| denied | Red | Horizontal shake |
| plan | Dashed | Preview (no action) |

Floating HUD status bar logs all actions with SF Symbols and `NSVisualEffectView`.

---

## Architecture

```
ghost (2MB static binary)
├── GhostKit (library)
│   ├── AXTree/        — AXUIElement reading, role mapping
│   ├── Pruning/       — 6-pass pipeline: strip → collapse → merge → promote → annotate → truncate
│   ├── Resolution/    — 4-strategy element targeting: exact → fuzzy → role+name → AXIdentifier
│   ├── Actions/       — press, type, select, key (CGEvent), navigate (NSWorkspace)
│   ├── Diff/          — Structural tree differ (match by role+name pairs)
│   ├── Explore/       — Autonomous BFS app cartography, state fingerprinting, .ghostmap format
│   ├── Serialization/ — Concise (indented text) + Detailed (JSON)
│   ├── Permissions/   — Rule engine, wildcard matching, transaction logging
│   ├── Snapshot/      — Capture, compare, check
│   └── Overlay/       — Core Animation highlights, spring physics, HUD status bar
└── Ghost (CLI)
    ├── Commands/      — observe, interact, explore, query, snapshot, overlay-demo
    ├── Transport/     — stdin/stdout JSON
    └── MCP/           — JSON-RPC 2.0 MCP server
```

---

## How it works

### Tree pruning

The raw macOS AX tree is verbose (500+ nodes for a typical window). Ghost's 6-pass pruning pipeline strips it down to what matters:

1. **Strip structural noise** — Remove unnamed groups, scroll areas, layout containers
2. **Collapse single-child** — A nameless wrapper around one button becomes just the button
3. **Merge adjacent text** — Three consecutive text nodes become one
4. **Promote interactive** — Strip empty non-interactive leaves
5. **Annotate state** — Add `(on)`, `(off)`, `(empty)`, `(selected)`, `(disabled)`
6. **Truncate lists** — Cap at `max_items` with count summary

### Element resolution

Paths like `"content > toggle > Wi-Fi"` are resolved through a fallback chain:

1. **Exact path** — Walk the tree matching each segment
2. **Fuzzy path** — Case-insensitive contains + Levenshtein distance ≤ 2
3. **Role + name search** — DFS for matching elements anywhere in the tree
4. **AXIdentifier** — Locale-independent developer-assigned IDs

### Ghost Explore

The exploration engine does BFS over the app's state space:

1. **Fingerprint** the current UI state (SHA-256 of structural skeleton, ignoring volatile values)
2. **Discover** all actionable elements (buttons, toggles, fields, links, menu items)
3. **Try** each action, recording whether it caused a state change, value toggle, or no effect
4. **Backtrack** (Escape / Back button) to try the next action
5. **Repeat** at each newly discovered state until limits are hit

Safety: dangerous actions (Delete, Erase, Reset, Quit) are skipped by default. Text fields are identified but not typed into unless `--text-fields` is set.

The result is a `.ghostmap` file — a JSON state graph with every reachable state, every action, every transition, and full tree snapshots. Query it with `ghost query`.

---

## Development

```bash
swift build
swift test   # 59 unit tests across 6 suites
```

## License

MIT. See [LICENSE](LICENSE).
