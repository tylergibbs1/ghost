# Ghost

**The last mile for AI agents on macOS. For the stuff bash can't reach.**

Swift. Native accessibility APIs. Instant.

---

## The Problem

An AI agent with a bash tool can already do most things on a computer. File management, text editing, git, builds, deployments, data processing, server admin, package management. Bash covers it. Add a browser automation tool and you've got the web too. Between the two, maybe 90% of real agent workflows are handled.

The remaining 10% is GUI-only territory. Things where no CLI or API equivalent exists, or where the task fundamentally requires seeing and interacting with a graphical interface.

Right now, agents handle this 10% by taking screenshots, sending them to a vision model, and clicking pixel coordinates. It works, sort of. It's also slow (~500-2000ms per action), expensive (thousands of vision tokens per screenshot), unreliable (vision models misread UI elements constantly), and has no security model whatsoever.

Ghost replaces the screenshot pipeline for this last mile. It reads the macOS accessibility tree (the same data VoiceOver uses) and gives agents a structured, token-efficient representation of the GUI. Actions target elements by name and role, not coordinates. Every action returns a diff of what changed. The agent never needs to "see" the screen.

---

## Where Ghost Fits

Ghost is complementary to bash, not a replacement. Bash handles the first 90%. Ghost handles the last 10% where no CLI exists.

### GUI-only applications

Some macOS apps have no CLI equivalent, or their CLI coverage is incomplete. System Settings is the poster child: `defaults write` covers some preferences, but network configuration, display arrangement, privacy permissions, and user accounts have no CLI equivalent. Native Apple apps (Preview, Photos, Contacts, Calendar) have partial AppleScript support that's unreliable and poorly documented. Third-party apps like 1Password, Figma, Notion, Slack, and Zoom have no local CLI at all. Installers, onboarding flows, and license activation dialogs are interactive GUI workflows with no scriptable alternative.

### Reading GUI state

Bash can change things but it can't tell you what a GUI currently looks like. Ghost answers questions like: "Is the Save button grayed out?", "What tab is active in Safari?", "Is there an error dialog on screen?", "What's the current value in this dropdown?" This matters for workflows that need to verify results, handle error states, or make decisions based on what the user is seeing.

### Cross-app GUI workflows

Some tasks span multiple GUI apps where the data lives in app state, not files. Read an email in Mail, then create a Calendar event. Check a password in 1Password, then enter it in Safari. Monitor a running app for a dialog, then respond to it.

### Helping non-technical users

When someone asks "How do I change my DNS settings?", the answer involves GUI steps. Ghost lets the agent see what the user sees and either guide them or do it directly. These users don't want to open a terminal.

### Hard Constraint: App Blocklist

Telling agents "prefer bash" in a tool description isn't enough. Models ignore soft guidance when a shinier tool is available. Ghost enforces this with a built-in app blocklist. If you try to observe or interact with an app that has a well-known CLI equivalent, Ghost returns an error:

```bash
ghost observe Terminal

# Error: Terminal is a CLI application. Use bash instead.
# Ghost is for GUI-only apps where no CLI alternative exists.
```

The default blocklist ships with Ghost and includes apps where bash is the right tool:

```json
{
  "blockedApps": [
    "Terminal",
    "iTerm2",
    "Warp",
    "Alacritty"
  ]
}
```

This is configurable. You can add apps to the blocklist or remove them. But the default ensures that agents don't reach for Ghost when bash would work. The tool description also tells agents to prefer bash, but the blocklist is the hard constraint that actually enforces it.

---

## Performance (Projected, Pending Benchmarks)

When Ghost is the right tool, it should be dramatically better than the screenshot alternative. These numbers are estimates based on the underlying API characteristics, not measured benchmarks. Actual performance will depend on app complexity, tree size, and pruning overhead. Honest benchmarks are a v0.1 deliverable.

| Metric | Screenshot-based | Ghost (estimated) |
|--------|-----------------|-------|
| Action latency | ~500-2000ms (capture + vision + click) | ~10-100ms (AX query + prune + diff) |
| Tokens per observation | ~2000-5000 (image) | ~50-200 (text tree) |
| Accuracy | Variable (vision model dependent) | Deterministic (structured data) |
| Cost per action | High (vision API call) | Near zero (local) |
| Concurrent app monitoring | 1 (active screen) | All running apps |
| State diffing | Pixel comparison | Structural diff |

The raw AX query is fast (<10ms for simple elements), but the full pipeline for a complex app (query all nodes, prune a 500-node tree, diff against previous state, serialize) will be slower. Even at the high end of the estimate, it's an order of magnitude faster than screenshots, and the token savings alone justify the tool.

---

## Install

```bash
brew install ghost
```

Requires macOS 13+ and Accessibility permission (granted once in System Settings > Privacy & Security > Accessibility).

---

## Quick Start

### CLI

```bash
# See what's on screen in System Settings
ghost observe "System Settings"

# Output:
# [app] System Settings
#   [window] System Settings
#     [sidebar]
#       [item] Wi-Fi (selected)
#       [item] Bluetooth
#       [item] Network
#       [item] General
#       ...
#     [content]
#       [heading] Wi-Fi
#       [toggle] Wi-Fi (on)
#       [text] Connected to "HomeNetwork"
#       [list] Known Networks (3 items)
#         [item] HomeNetwork (connected)
#         [item] OfficeWiFi
#         [item] CoffeeShop

# Toggle Wi-Fi off
ghost interact "System Settings" press "content > toggle > Wi-Fi"

# Check a specific part of the UI (saves tokens)
ghost observe "System Settings" --focus "content"

# See all running apps
ghost observe

# Save state before making changes
ghost snapshot "System Settings" capture "before-changes"

# ... make changes ...

# See everything that changed
ghost snapshot "System Settings" compare "before-changes"
```

### As a Library (for Agent Frameworks)

```typescript
import { Ghost } from "ghost-client";

const ghost = new Ghost(); // spawns the Swift binary

// See what apps are running
const desktop = await ghost.observe();

// Read state from a GUI-only app
const settings = await ghost.observe("System Settings", {
  focus: "content"
});

// Interact and get the diff back in one call
const result = await ghost.interact(
  "System Settings", "press", "content > toggle > Wi-Fi"
);
console.log(result.diff);
// [{ type: "changed", path: "content > toggle > Wi-Fi", from: "on", to: "off" }]

// Or get the full updated tree + diff
const result = await ghost.interact(
  "System Settings", "select", "sidebar > Network",
  { includeTree: true }
);

ghost.close();
```

### MCP Server

Ghost ships as an MCP server so any MCP-compatible agent can use it directly:

```bash
ghost serve --mcp
```

Three tools exposed: `ghost_observe`, `ghost_interact`, `ghost_snapshot`. See [Tool Design](#tool-design) for full schemas.

---

## Core Concepts

### The Accessibility Tree Is the Interface

macOS maintains a full accessibility tree for every running application via the AX API. VoiceOver uses it. Screen readers use it. Ghost makes it the primary interface for agents: always available, always current, token-efficient.

Ghost prunes the raw AX tree to remove noise:

- Layout containers with a single meaningful child get collapsed
- Decorative/structural nodes (groups, scroll views) get stripped unless labeled
- Adjacent static text nodes get merged
- Offscreen/hidden elements get marked or omitted
- Interactive elements get promoted with their available actions

```bash
ghost observe "1Password"

# [app] 1Password
#   [window] 1Password
#     [sidebar]
#       [item] All Items (247)
#       [item] Favorites (12)
#       [item] Login (184)
#       [item] Credit Card (8)
#     [search] Search (empty)
#     [list] Items (showing 10 of 247)
#       [item] GitHub - login (username: tyler@...)
#       [item] AWS Console - login
#       ...
#     [detail]
#       [heading] GitHub
#       [field] username: tyler@example.com
#       [field] password: ••••••••••
#       [button] Copy Password
#       [button] Edit
```

An agent only cares about the sidebar? Use `--focus`:

```bash
ghost observe "1Password" --focus "sidebar"

# [sidebar]
#   [item] All Items (247)
#   [item] Favorites (12)
#   [item] Login (184)
#   [item] Credit Card (8)
```

That's maybe 20 tokens instead of 100+. Don't waste context on UI the agent doesn't care about.

### Actions Return Diffs Automatically

The most common agent pattern is: observe the UI, do something, observe again to see what changed. That's three round trips. Ghost collapses this to one. Every `ghost_interact` call returns the structural diff showing what changed.

```bash
ghost interact "System Settings" select "sidebar > Network"

# Action: select [item] Network
# Result: success
# Diff:
#   [changed] sidebar > selected: "Wi-Fi" -> "Network"
#   [changed] content > heading: "Wi-Fi" -> "Network"
#   [changed] content: new children (VPN, Firewall, DNS, etc.)
```

If the agent also needs the full updated tree (not just the diff), it passes `--include-tree` and gets both in the same response. One tool call instead of three.

### Actions Are Typed, Not Coordinate-Based

Instead of "click at (342, 217)", agents issue structured commands:

```bash
# Press a button
ghost interact "1Password" press "detail > Copy Password"

# Type into a field
ghost interact "System Settings" type "DNS Servers" --value "1.1.1.1"

# Select from a dropdown or sidebar
ghost interact "System Settings" select "sidebar > Network"

# Keyboard shortcut
ghost interact "Keynote" key "editor" --value "cmd+s"

# Navigate to an app/window
ghost interact desktop navigate "System Settings"
```

Actions resolve targets against the accessibility tree, not screen coordinates. The AX API provides built-in actions for every interactive element. No mouse simulation needed for the vast majority of interactions.

### Element Resolution

Path-based targeting (`"content > toggle > Wi-Fi"`) is the primary interface, but exact paths are fragile. Apps restructure their UI across versions. Element names change with localization. Multiple elements can have the same label.

Ghost resolves targets through a fallback chain:

1. **Exact path match.** `"content > toggle > Wi-Fi"` walks the tree literally. Fastest, most precise. Works when you know the exact structure from a recent `ghost_observe` call.

2. **Fuzzy path match.** If the exact path doesn't resolve, Ghost tries partial matching: find any element with role=toggle and name containing "Wi-Fi" anywhere in the content subtree. This handles minor tree restructuring between app versions.

3. **Role + name search.** If the path doesn't match at all, Ghost searches the entire app tree for an element matching the role and name. `"toggle > Wi-Fi"` without the `content >` prefix would still find the right element.

4. **AXIdentifier fallback.** Many elements have locale-independent `AXIdentifier` attributes that don't change across localizations. Ghost can use these when name-based matching fails due to language differences.

When multiple elements match, Ghost returns an error with the candidates and asks the agent to be more specific (or use the `detailed` format from `ghost_observe` which includes unique element IDs).

This is probably the biggest engineering challenge in the project. The resolution logic needs to be reliable enough that agents don't constantly fail to find elements, but strict enough that they don't accidentally target the wrong one. Getting this right is what makes Ghost useful vs. frustrating.

### Multi-App Awareness

Ghost maintains trees for all running applications simultaneously. An agent can observe the whole desktop in ~200 tokens, then zoom into the specific app it needs.

```bash
ghost observe

# [desktop]
#   [app] System Settings (active)
#     [window] System Settings
#   [app] Safari
#     [window] Router Admin - 192.168.1.1
#   [app] Terminal
#     [window] ~/project (zsh)
#   [app] 1Password
#     [window] 1Password (locked)
#   [menubar]
#     [menu] Apple
#     [menu] System Settings
```

This is useful for workflows that span multiple apps: check a password in 1Password, then enter it into a website in Safari, then verify a setting in System Settings.

---

## Tool Design

Ghost exposes three MCP tools. The design follows Anthropic's tool design principles: fewer tools that each do more, built-in filtering to control token usage, and responses that eliminate the need for follow-up calls.

### Why Three Tools, Not Seven

An earlier design had separate tools for `tree`, `desktop`, `watch`, `act`, `diff`, `snapshot`, and `restore`. That's too many. Agents waste tool calls on the most common workflow (observe -> act -> observe again), and overlapping tools create ambiguity about which one to use.

The consolidated design:

| Before | After | Why |
|--------|-------|-----|
| `ghost_tree`, `ghost_desktop`, `ghost_watch` | `ghost_observe` | All read operations. Focus parameter controls scope. Format parameter controls verbosity. |
| `ghost_act` + follow-up `ghost_tree` | `ghost_interact` | Returns diff automatically, eliminating the follow-up call. Optional `include_tree` for the full state. |
| `ghost_diff`, `ghost_snapshot`, `ghost_restore` | `ghost_snapshot` | All time-based state operations: capture, compare, check. |

### ghost_observe

Returns the current accessibility tree for one or all macOS applications. This is the primary read tool.

```json
{
  "name": "ghost_observe",
  "description": "Returns the current accessibility tree for one or all macOS applications. Use this tool ONLY when you need to read GUI state that is not accessible via bash or CLI tools. For file operations, use bash. For git, use bash. For most system administration, try CLI tools first (networksetup, defaults, diskutil, etc.). Ghost is for GUI-only apps (System Settings, 1Password, Figma, native Apple apps) and for reading UI state (is a button enabled, what tab is active, what dialog is showing). Note: CLI apps like Terminal and iTerm2 are blocklisted and will return an error. Returns a pruned, token-efficient tree stripped of layout noise. Use 'focus' to zoom into a specific part of the UI. Use 'format' to control response verbosity. When called with no app, returns a summary of all running apps (~200 tokens). With an app, returns the full pruned tree (~50-200 tokens). With app + focus, returns just the targeted subtree (~20-50 tokens).",
  "input_schema": {
    "type": "object",
    "properties": {
      "app": {
        "type": "string",
        "description": "Application name to observe, e.g. 'System Settings', '1Password', 'Keynote'. Omit to get a summary of all running apps with their window titles and states."
      },
      "focus": {
        "type": "string",
        "description": "Path to a specific subtree to zoom into, e.g. 'content', 'sidebar', 'toolbar > format'. Returns only that subtree and its children. Use this to save tokens when you already know which part of the UI you care about."
      },
      "format": {
        "type": "string",
        "enum": ["concise", "detailed"],
        "description": "concise (default): compact indented text tree optimized for LLM context windows, uses role labels like [button], [textfield], etc. detailed: JSON with element IDs, available actions per element, bounding rects, and full state metadata. Use detailed when you need to disambiguate between elements with the same name."
      },
      "max_items": {
        "type": "integer",
        "description": "For lists, tables, and other repeating elements: maximum items to include before truncating with a count summary. Default: 10. Set higher if you need to scan a long list for a specific item."
      }
    }
  },
  "input_examples": [
    {},
    { "app": "System Settings" },
    { "app": "System Settings", "focus": "content" },
    { "app": "1Password", "focus": "detail", "format": "detailed" },
    { "app": "Keynote", "focus": "slides", "max_items": 30 }
  ]
}
```

**Concise response example** (~80 tokens):
```
[app] System Settings
  [window] System Settings
    [sidebar]
      [item] Wi-Fi (selected)
      [item] Bluetooth
    [content]
      [heading] Wi-Fi
      [toggle] Wi-Fi (on)
      [text] Connected to "HomeNetwork"
```

**Detailed response example** (~250 tokens):
```json
{
  "app": "System Settings",
  "windows": [{
    "name": "System Settings",
    "children": [{
      "role": "sidebar",
      "children": [
        { "id": "s1", "role": "item", "name": "Wi-Fi", "selected": true },
        { "id": "s2", "role": "item", "name": "Bluetooth", "selected": false }
      ]
    }, {
      "role": "content",
      "children": [
        { "id": "c1", "role": "heading", "name": "Wi-Fi" },
        { "id": "c2", "role": "toggle", "name": "Wi-Fi", "value": true, "actions": ["press"] }
      ]
    }]
  }]
}
```

### ghost_interact

Performs a UI interaction on a macOS application and returns what changed. This is the primary write tool.

```json
{
  "name": "ghost_interact",
  "description": "Performs a UI interaction on a macOS application and returns what changed. Use this ONLY for GUI interactions that cannot be done via bash or CLI tools. The action targets an element by its accessibility tree path (from ghost_observe output), not by screen coordinates. Returns a structural diff showing exactly what changed in the UI. If the action is blocked by permission rules, returns a 'pending_approval' status. Use ghost_observe first if you need to find the target element's tree path.",
  "input_schema": {
    "type": "object",
    "properties": {
      "app": {
        "type": "string",
        "description": "Application name, e.g. 'System Settings', '1Password', 'Keynote'. Use 'desktop' for system-level actions like navigating to a different app."
      },
      "action": {
        "type": "string",
        "enum": ["press", "type", "select", "key", "scroll", "navigate", "drag"],
        "description": "The kind of interaction. press: activate a button, menu item, link, or checkbox. type: enter text into a text field (replaces current content). select: choose an option from a dropdown, list, or radio group. key: send a keyboard shortcut. scroll: scroll a container up or down. navigate: bring an app or window to the front. drag: drag one element onto another."
      },
      "target": {
        "type": "string",
        "description": "Accessibility tree path to the target element, using the names shown in ghost_observe output. Use '>' to specify a path, e.g. 'content > toggle > Wi-Fi', 'sidebar > Network'. For navigate, this is the app or window name."
      },
      "value": {
        "type": "string",
        "description": "The value for the action. For type: the text to enter. For select: the option label to choose. For key: the shortcut string, e.g. 'cmd+s'. For scroll: 'up' or 'down'. For drag: the drop target path. Not used for press or navigate."
      },
      "include_tree": {
        "type": "boolean",
        "description": "If true, returns the full updated accessibility tree after the action in addition to the diff. Default: false. Use when you need to plan your next action without a separate ghost_observe call."
      }
    },
    "required": ["app", "action", "target"]
  },
  "input_examples": [
    { "app": "System Settings", "action": "press", "target": "content > toggle > Wi-Fi" },
    { "app": "System Settings", "action": "select", "target": "sidebar > Network" },
    { "app": "System Settings", "action": "type", "target": "DNS Servers", "value": "1.1.1.1" },
    { "app": "1Password", "action": "press", "target": "detail > Copy Password" },
    { "app": "desktop", "action": "navigate", "target": "System Settings" },
    { "app": "Keynote", "action": "key", "target": "editor", "value": "cmd+s" },
    { "app": "System Settings", "action": "select", "target": "sidebar > Network", "include_tree": true }
  ]
}
```

**Response example** (action succeeds, diff only):
```json
{
  "status": "success",
  "action": "press",
  "target": "[toggle] Wi-Fi",
  "diff": [
    { "type": "changed", "path": "content > toggle > Wi-Fi", "from": "on", "to": "off" },
    { "type": "removed", "path": "content > text > Connected to \"HomeNetwork\"" },
    { "type": "changed", "path": "content > list > Known Networks", "detail": "grayed out" }
  ]
}
```

**Response example** (action blocked by permissions):
```json
{
  "status": "pending_approval",
  "action": "press",
  "target": "[button] Erase All Content and Settings",
  "rule": "Press(* > * > Erase *) [deny, user settings]",
  "message": "This action is blocked by a deny rule. Update permissions in .ghost/settings.json to allow it."
}
```

### ghost_snapshot

Captures, compares, or checks UI state for an application. Use for multi-step workflows where you need to track cumulative changes or verify the UI reached an expected state.

```json
{
  "name": "ghost_snapshot",
  "description": "Manages saved accessibility tree states for an application. Use 'capture' to save the current UI state before starting a multi-step workflow. Use 'compare' to get a full diff between the current state and a saved snapshot. Use 'check' to verify whether the current state matches a snapshot (boolean, for assertions). Snapshots are stored in memory for the session duration.",
  "input_schema": {
    "type": "object",
    "properties": {
      "app": {
        "type": "string",
        "description": "Application name."
      },
      "action": {
        "type": "string",
        "enum": ["capture", "compare", "check"],
        "description": "capture: save current state with a label. compare: diff current state against a saved snapshot. check: boolean match against a saved snapshot."
      },
      "label": {
        "type": "string",
        "description": "Short name for this snapshot, e.g. 'before-config-change', 'clean-state'. Scoped per app."
      }
    },
    "required": ["app", "action", "label"]
  },
  "input_examples": [
    { "app": "System Settings", "action": "capture", "label": "before-dns-change" },
    { "app": "System Settings", "action": "compare", "label": "before-dns-change" },
    { "app": "1Password", "action": "check", "label": "unlocked" }
  ]
}
```

### Token Efficiency

| Pattern | Screenshot approach | Ghost |
|---------|-------------------|-------|
| "Is Wi-Fi on in System Settings?" | Screenshot (~3000 tokens) + vision call | `ghost_observe` with focus (~30 tokens) |
| "Toggle Wi-Fi and confirm it changed" | 2 screenshots + 2 vision calls + coordinate click | `ghost_interact` returns diff (~50 tokens) |
| "Navigate to Network settings and read DNS" | 3+ screenshots, each ~3000 tokens | `ghost_interact` + `ghost_observe` with focus (~80 tokens total) |

---

## Permission System

Ghost uses a permission model inspired by Claude Code. Read operations (`ghost_observe`, `ghost_snapshot`) are always free. Write operations (`ghost_interact`) require explicit permission.

### Permission Rules

Rules follow the format `Action` or `Action(specifier)`:

```json
{
  "permissions": {
    "allow": [
      "Observe",
      "Snapshot",
      "Scroll",
      "Navigate",
      "Press(System Settings > content > *)",
      "Select(System Settings > sidebar > *)",
      "Type(System Settings > content > *)",
      "Press(1Password > detail > Copy *)",
      "Key(Keynote cmd+s)"
    ],
    "deny": [
      "Press(* > * > Delete)",
      "Press(* > * > Erase *)",
      "Press(* > * > Reset *)",
      "Key(* cmd+q)",
      "Navigate(Disk Utility)",
      "Navigate(Migration Assistant)",
      "Type(Mail *)",
      "Type(Messages *)",
      "Press(Mail > * > Send)",
      "Drag(*)"
    ]
  }
}
```

Deny always wins. Even if you allow all System Settings interactions, a global deny on "Erase" buttons still blocks it.

### Specifier Format

Specifiers use the accessibility tree path. Wildcards work the same as Claude Code's bash wildcards:

| Rule | Matches |
|------|---------|
| `Press(System Settings > content > *)` | Any pressable element in the content pane |
| `Select(System Settings > sidebar > *)` | Any sidebar navigation |
| `Press(* > * > Save)` | Save button in any app |
| `Type(System Settings > content > *)` | Typing in any content field |
| `Key(Keynote cmd+s)` | Save shortcut in Keynote |
| `Key(* cmd+shift+delete)` | Empty trash shortcut in any app |

### Permission Modes

| Mode | Description |
|------|-------------|
| `plan` | Read only. Agent sees the full tree but can't interact. |
| `default` | Prompts for each new action type. "Allow always" saves a rule. |
| `allowlist` | Only pre-approved actions work. Everything else returns permission denied. |
| `open` | All actions allowed. Only for sandboxed/isolated environments. |

### Confirmation Prompts

When the agent tries an unapproved action in `default` mode:

```
┌─────────────────────────────────────────────┐
│ Ghost: action requires permission           │
│                                             │
│ Action:  Press                              │
│ App:     System Settings                    │
│ Target:  [button] "Reset Network Settings"  │
│ Context: Network pane active                │
│                                             │
│ [Allow once] [Allow for session]            │
│ [Allow always] [Deny]                       │
└─────────────────────────────────────────────┘
```

"Allow always" saves a persistent rule. "Deny" saves a deny rule. Same muscle memory as Claude Code.

### Settings Precedence

1. **Managed settings** (org-level, cannot be overridden)
2. **CLI flags** (session overrides)
3. **Project settings** (`.ghost/settings.json`)
4. **User settings** (`~/.ghost/settings.json`)

If an action is denied at any level, no other level can allow it.

### Default Configuration

Ships with safe defaults:

```json
{
  "permissions": {
    "allow": [
      "Observe",
      "Snapshot",
      "Scroll",
      "Navigate"
    ],
    "deny": [
      "Press",
      "Type",
      "Select",
      "Drag",
      "Key"
    ]
  },
  "defaultMode": "default"
}
```

Out of the box: the agent can see everything and navigate between windows, but can't press, type, or interact until you approve. Each approval builds the allowlist organically.

### Transaction Log

Every action is logged with full context:

```json
{
  "timestamp": "2026-03-21T14:23:01Z",
  "tool": "ghost_interact",
  "action": "press",
  "app": "System Settings",
  "target": "[button] Reset Network Settings",
  "context": "Network pane active",
  "result": "denied",
  "rule": "Press(* > * > Reset *) [deny, user settings]"
}
```

---

## Visual Overlay

When a human is watching, Ghost can show exactly what the agent is doing on screen in real time. Every AX element already has `AXPosition` and `AXSize` attributes giving its exact screen coordinates and dimensions. Ghost knows where everything is physically located, even though it never uses coordinates for interaction.

The overlay is a transparent, click-through `NSWindow` that sits above all other windows. It doesn't intercept any mouse or keyboard events. It just draws highlights and annotations on top of the real UI.

### What It Shows

**`ghost_observe`** — a brief, subtle pulse around the app or subtree being read. Just enough to show "the agent is looking here."

**`ghost_interact press`** — a ripple animation on the target button, similar to VoiceOver's visual feedback when it activates an element. A small tooltip shows the element name.

**`ghost_interact type`** — the target text field gets a colored border. The text appears character by character, even though the actual `AXSetValue` happens instantly. Makes it feel like someone is actually typing.

**`ghost_interact select`** — the dropdown or list item highlights briefly, then the selected option flashes.

**`ghost_interact navigate`** — a transition indicator as the target app comes to front.

**`ghost_interact key`** — the keyboard shortcut appears as a brief HUD (like the macOS volume/brightness overlay), then the target element pulses.

Each action type has its own color so you can tell at a glance what kind of interaction is happening:

| Action | Color |
|--------|-------|
| observe | Gray (subtle) |
| press | Blue |
| type | Green |
| select | Purple |
| key | Orange |
| navigate | White/system accent |
| scroll | Light gray |

### Status Bar

A small floating bar (similar to the macOS screenshot toolbar) sits at the top of the screen and shows a running log of agent actions:

```
┌──────────────────────────────────────────────────┐
│ 👻 Ghost                                         │
│ ● observe System Settings > content              │
│ ● press [toggle] Wi-Fi                           │
│ ● diff: Wi-Fi on → off                           │
└──────────────────────────────────────────────────┘
```

This scrolls as actions happen. Clicking it expands a full session log.

### Native Permission Prompts

In `default` mode, permission confirmations are native macOS popovers anchored to the actual element the agent wants to interact with, not terminal prompts. The overlay highlights the element in yellow, and a popover appears right next to it:

```
              ┌───────────────────────────────────┐
              │ Ghost wants to press this button   │
              │ [button] "Reset Network Settings"  │
              │ App: System Settings               │
              │                                    │
              │ [Allow once] [Always] [Deny]       │
              └───────────────┬───────────────────┘
                              ▼
                ┌─────────────────────┐
                │ Reset Network       │  ← actual button on screen,
                │ Settings            │    highlighted in yellow
                └─────────────────────┘
```

You can see exactly what the agent is targeting and approve or deny it with full visual context.

### Overlay Modes by Permission Level

The overlay integrates with the permission system:

| Permission mode | Overlay behavior |
|----------------|-----------------|
| `plan` | Elements highlight in yellow with dashed borders. Shows what the agent *would* do, but no actions are taken. Good for previewing a workflow. |
| `default` | Highlights the target element, pauses for confirmation on unapproved actions, then shows the action animation and diff result. |
| `allowlist` | Actions animate as they happen with no pauses. Fast visual feedback for pre-approved workflows. |
| `open` | Same as allowlist. Optional. |

### Opt-in

The overlay is off by default. Headless and server use cases don't need it. Enable it via CLI flag or settings:

```bash
# Enable overlay for MCP server
ghost serve --mcp --overlay

# Enable overlay for CLI
ghost interact "System Settings" press "toggle > Wi-Fi" --overlay
```

Or in settings:

```json
{
  "overlay": {
    "enabled": true,
    "statusBar": true,
    "animationSpeed": "normal"
  }
}
```

Animation speed can be `"fast"` (150ms per action, for experienced users watching a fast agent), `"normal"` (300ms, the default), or `"slow"` (600ms, for demos or when you want to follow along carefully).

### Why This Matters

Two reasons.

**Trust.** When an autonomous agent is doing stuff on your desktop, seeing what it's targeting before it acts is the difference between "I trust this" and "I'm terrified." The overlay makes the agent's behavior legible. If it's about to click the wrong button, you can see that immediately and hit deny. Without the overlay, you're relying on terminal logs after the fact.

**Debugging.** When an agent workflow isn't working, the overlay shows you exactly where it's going wrong. Is it targeting the wrong element? Is the AX tree path not resolving? Is it finding the right element but the action isn't having the expected effect? All of this is visible at a glance rather than buried in JSON logs.

---

## Architecture

```
┌─────────────────────────────────────┐
│          Agent (LLM)                │
│  primary tools: bash, web browser   │
│  last mile: ghost                   │
└──────────┬──────────────────────────┘
           │ JSON (stdin/stdout, local HTTP, or MCP)
┌──────────▼──────────────────────────┐
│       ghost (Swift binary)          │
│                                     │
│  ┌─────────────┐  ┌──────────────┐  │
│  │ Tree Builder │  │ Permissions  │  │
│  │ - AX query   │  │ - Rules      │  │
│  │ - Prune      │  │ - Confirm    │  │
│  │ - Focus      │  │ - Log        │  │
│  │ - Serialize  │  │              │  │
│  └──────┬──────┘  └──────┬───────┘  │
│  ┌──────▼──────┐  ┌──────▼───────┐  │
│  │   Actions   │  │   Watcher    │  │
│  │ - AXPress   │  │ - AXObserver │  │
│  │ - AXSet     │  │ - NSWorksp.  │  │
│  │ - CGEvent   │  │ - Debounce   │  │
│  │   (fallback)│  │ - Diff       │  │
│  └──────┬──────┘  └──────────────┘  │
│  ┌──────▼──────┐  ┌──────────────┐  │
│  │  Snapshots  │  │   Overlay    │  │
│  │ - Capture   │  │ - NSWindow   │  │
│  │ - Compare   │  │ - Highlight  │  │
│  │ - Check     │  │ - Animate    │  │
│  └─────────────┘  │ - StatusBar  │  │
│                   │ - Confirm    │  │
│  ┌─────────────┐  └──────────────┘  │
│  │  Transport  │                    │
│  │ - stdio     │                    │
│  │ - HTTP      │                    │
│  │ - MCP       │                    │
│  └─────────────┘                    │
└─────────────────────────────────────┘
           │
┌──────────▼──────────────────────────┐
│    macOS Accessibility API          │
│  AXUIElement, AXObserver,           │
│  CGEvent, NSWorkspace               │
└─────────────────────────────────────┘
```

### Swift Binary (ghost)

The core. Handles all OS interaction, tree building, action execution, and the permission engine. Compiles to a single static binary with no runtime dependencies. Written in Swift because the macOS Accessibility API (`AXUIElement`, `AXObserver`, `CGEvent`) is a native C/Objective-C API that Swift calls directly with zero FFI overhead.

```
ghost/
├── Sources/
│   ├── Tree/        # AX tree reading, pruning, focus filtering, serialization
│   ├── Actions/     # Action execution (AXPress, AXSetValue, CGEvent)
│   ├── Watch/       # AX notifications, change detection, debouncing, diffing
│   ├── Snapshot/    # Capture, compare, check
│   ├── Overlay/     # Transparent NSWindow, element highlights, animations, status bar
│   ├── Permissions/ # Rule parsing, matching, confirmation UI, logging
│   ├── Transport/   # stdin/stdout JSON, HTTP server, MCP server
│   ├── CLI/         # Command-line interface
│   └── main.swift
├── Package.swift
└── Tests/
```

### TypeScript Client (ghost-client)

Thin wrapper that spawns the Swift binary and provides a typed API for agent frameworks:

```typescript
import { Ghost } from "ghost-client";

const ghost = new Ghost({
  permissions: "./ghost-settings.json",
  mode: "default"
});

const tree = await ghost.observe("System Settings");
const result = await ghost.interact(
  "System Settings", "press", "content > toggle > Wi-Fi"
);
await ghost.snapshot("System Settings", "capture", "before-change");

ghost.close();
```

Published to npm. Works with any TypeScript/JavaScript agent framework.

---

## Tree Pruning

The raw macOS AX tree is verbose. A typical System Settings window might have 500+ nodes. Most are layout containers, decorative elements, or internal framework details.

Ghost's pruning pipeline:

1. **Collapse single-child containers.** A `Group` containing one `Button` becomes just the `Button`.
2. **Strip structural noise.** `ScrollArea`, `SplitGroup`, `LayoutArea` nodes are removed unless they carry meaningful labels.
3. **Merge adjacent text.** Three consecutive `StaticText` nodes become one.
4. **Promote interactive elements.** Buttons, links, text fields, checkboxes float up to the nearest meaningful ancestor.
5. **Annotate state.** Checkboxes get `(checked)` / `(unchecked)`. Toggles get `(on)` / `(off)`. Text fields get their current value or `(empty)`. Dropdowns get their selected option.
6. **Truncate large lists.** Lists with many items show the first N plus a count. Configurable via `max_items`.
7. **Mark visibility.** Offscreen elements get marked or omitted based on config.

The goal: every node in the pruned tree is something the agent might want to read or interact with. Nothing else.

### Serialization Formats

**Concise** (default, for LLM context):
```
[window] System Settings
  [sidebar]
    [item] Wi-Fi (selected)
    [item] Network
  [content]
    [heading] Wi-Fi
    [toggle] Wi-Fi (on)
    [text] Connected to "HomeNetwork"
```

**Detailed** (JSON, for programmatic use or disambiguation):
```json
{
  "role": "window",
  "name": "System Settings",
  "children": [
    {
      "role": "sidebar",
      "children": [
        { "id": "s1", "role": "item", "name": "Wi-Fi", "selected": true, "actions": ["select"] },
        { "id": "s2", "role": "item", "name": "Network", "selected": false, "actions": ["select"] }
      ]
    },
    {
      "role": "content",
      "children": [
        { "id": "c1", "role": "toggle", "name": "Wi-Fi", "value": true, "actions": ["press"] }
      ]
    }
  ]
}
```

---

## Known Challenges

### Accessibility Tree Quality (The Big Risk)

This is the thing that could make or break the project. The quality of AX trees varies wildly across apps. Apple's own apps (System Settings, Finder, Safari, Mail) have excellent trees because Apple dogfoods VoiceOver internally. Well-built native apps (1Password, Things, Bear) tend to have good trees too.

But the apps where agents most want GUI access are often the ones with the worst trees. Slack, Notion, Discord, and Figma are all Electron or custom-rendered. Their AX trees range from "messy but usable" to "barely functional." Web content mapped to native AX nodes produces inconsistent hierarchies, missing labels, and phantom elements.

This means the 10% of workflows that Ghost is supposed to cover might shrink to 5% once you account for apps with unusable AX data. That's still valuable (System Settings alone justifies the tool), but it's worth being honest about.

The v0.1 test list includes Electron apps specifically to find out early whether this is a solvable problem (app-specific pruning rules, DOM bridging) or a fundamental limitation. If the answer is "fundamental limitation," the positioning shifts to "Ghost works great for native macOS apps and some well-behaved third-party apps" rather than "Ghost works for everything."

### Electron Apps

Slack, VS Code, Discord, and many other apps are Electron. Their AX trees can be inconsistent because web content gets mapped to native AX nodes imperfectly. Ghost will need app-specific handling for major Electron apps, potentially bridging to their internal DOM or applying custom pruning rules. Most Electron apps fall into the "GUI-only app" category where Ghost is the right tool regardless, so this is worth solving even if it's hard.

### App Updates Breaking Everything

This is the maintenance burden nobody talks about. When System Settings changes its layout in macOS 16, every path-based permission rule, every pruning heuristic, and every element resolution pattern might need updating. When Slack ships a new version with a restructured UI, app-specific pruning rules might break.

Ghost has an ongoing maintenance cost that scales with the number of supported apps. Mitigation strategies include: relying on roles and AXIdentifiers rather than names/paths wherever possible (these are more stable across versions), building a test suite that runs against real apps and alerts on tree structure changes, and keeping app-specific logic minimal so most of the work is done by general-purpose pruning.

This is fundamentally a "living software" problem. Ghost isn't something you ship and walk away from. It needs ongoing attention as the macOS ecosystem evolves.

### Custom-Drawn UI

Apps that draw their own UI with Metal, OpenGL, or custom drawing (games, some creative tools) won't have meaningful AX trees. Ghost detects this (suspiciously empty tree for a visible window) and reports it to the agent. These apps are out of scope.

### Dynamic Content

Some apps update rapidly (video players, animations, live data). Ghost debounces AX notifications and waits for the tree to stabilize before reporting changes. The debounce interval is configurable.

### Permission Grant

macOS requires the user to grant Accessibility permission in System Settings > Privacy & Security > Accessibility. This is a one-time setup, similar to granting screen recording permission for screenshot-based tools. Ghost provides a setup command that walks the user through it:

```bash
ghost setup
# Opens System Settings to the right pane, walks through permission grant
```

---

## What Ghost Is NOT

- **Not a replacement for bash.** Ghost enforces this with an app blocklist. CLI apps return an error. If there's a CLI way to do something, use the CLI.
- **Not a screen reader.** Same APIs, different output. Ghost produces structured data for agents, not audio.
- **Not a screenshot tool.** Never captures pixels.
- **Not a macro recorder.** Actions target elements by role and name, not screen coordinates.
- **Not cross-platform (yet).** macOS first. Windows (UI Automation API) and Linux (AT-SPI) are future work.
- **Not universal.** Apps with custom-drawn UIs, games, and GPU-rendered content are out of scope. Some Electron apps may have AX trees too messy to be useful. Ghost is honest about what it can and can't handle.

---

## Roadmap

### v0.1 - Foundation
- [ ] AX tree reading for any running application
- [ ] Tree pruning pipeline (collapse, strip, merge, promote)
- [ ] Element resolution with fuzzy matching fallback chain
- [ ] Focus filtering (subtree selection)
- [ ] Concise and detailed serialization formats
- [ ] Basic actions: press, type, select, key, navigate
- [ ] Auto-diff on every action
- [ ] App blocklist (Terminal, iTerm2, and other CLI apps)
- [ ] stdin/stdout JSON transport
- [ ] CLI: `ghost observe`, `ghost interact`
- [ ] Performance benchmarks (tree query, prune, diff, serialize) for simple and complex apps
- [ ] Tested against native apps: System Settings, Finder, Safari, 1Password, Keynote
- [ ] Tested against Electron apps: Slack, VS Code (to assess AX tree quality early)
- [ ] AX tree quality report: honest assessment of which app categories produce usable trees

### v0.2 - Permissions + Safety
- [ ] Permission rule engine (allow/deny/ask)
- [ ] Confirmation prompts in default mode
- [ ] Settings file hierarchy (managed, user, project)
- [ ] Transaction logging
- [ ] Default safe configuration

### v0.3 - Visual Overlay
- [ ] Transparent click-through overlay window
- [ ] Element highlighting with action-specific colors and animations
- [ ] Floating status bar with action log
- [ ] Native popover confirmation prompts anchored to target elements
- [ ] Plan mode visual preview (dashed borders, no actions taken)
- [ ] Animation speed settings (fast/normal/slow)
- [ ] `--overlay` flag for CLI and MCP server

### v0.4 - Snapshots + Watching
- [ ] Snapshot capture, compare, check
- [ ] AX notification listener for streaming changes
- [ ] Debounced change detection
- [ ] CLI: `ghost snapshot`

### v0.5 - Agent Integration
- [ ] MCP server mode (`ghost serve --mcp`)
- [ ] HTTP server mode (`ghost serve --http`)
- [ ] TypeScript client package (ghost-client on npm)
- [ ] Python client package (ghost-client on pip)

### v0.6 - Polish
- [ ] Electron app-specific handling (Slack, Discord, Notion)
- [ ] Performance benchmarks against screenshot-based tools
- [ ] Homebrew formula
- [ ] Agent SDK examples (Claude, OpenAI, LangChain)
- [ ] Per-app regression test suite (detects tree structure changes across macOS/app updates)

### Future
- [ ] Windows support (UI Automation API)
- [ ] Linux support (AT-SPI)
- [ ] Recording/replay for deterministic testing
- [ ] Mock mode for agent development without a live desktop

---

## License

MIT
