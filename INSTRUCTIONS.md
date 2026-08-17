# Project Instructions

## Coding Workflow Principles

### 1. Plan Mode First
- Use plan mode for any non-trivial task
- Write detailed specs up front
- Reduce ambiguity before writing code
- Lightweight inline plan for smaller tasks

### 2. Verify Relentlessly
- Watch like a hawk in a good IDE
- Check assumptions, edge cases, tradeoffs
- Run tests, review diffs, verify correctness
- Don't blindly accept — stay in the loop

### 3. Keep It Simple
- Avoid overengineering and bloated abstractions
- Prefer 100 lines over 1000
- Clean up dead code and cruft
- Ask: "Is there a simpler way?"

### 4. Surgical Edits Only
- Change only what's necessary
- Don't touch unrelated code or comments
- Don't "improve" things that aren't broken
- Minimize side effects and churn

### 5. Goal-Driven Execution
- Give clear success criteria
- Write tests first, then make them pass
- Use tools (e.g., browser MCP) in the loop
- Let the agent iterate until the goal is met

### 6. Parallelize with Subagents
- Offload research, exploration, analysis
- Use subagents to keep context clean
- One task per subagent for focus
- Merge results back with judgment

## Core Principles

- **Simplicity First**: Minimal code that solves the problem. Nothing speculative.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Only touch what's necessary. No side effects. No new bugs.

## Engineer Mindset

- **Tenacity** — Agents never get tired. Relentless iteration beats giving up. Stamina is a force multiplier.
- **Leverage** — Give success criteria and watch it go. Imperative → Declarative. Multiply your leverage.
- **Fun** — Remove drudgery, focus on creativity. More courage, less blocking.
- **Atrophy** — Writing and reading code are different. Stay sharp intentionally.
- **Speedups ≠ Just Faster** — Do more, not just faster. Expand what you can build, not just how quickly.
- **Slopocalypse** — Brace for AI slop in 2026. Hype will be loud. Signal requires judgment.

## Research-First Implementation

Before implementing ANY new idea, feature, library, or pattern:

1. **Search first** — Use `creep search` to find documentation, best practices, and known issues
2. **Scrape the docs** — Use `creep scrape` on the most relevant result to get full context
3. **Evaluate** — Check for:
   - Is this the right approach? Are there better alternatives?
   - Known bugs, breaking changes, or deprecation warnings
   - Version compatibility with existing dependencies
   - Community consensus on the pattern
4. **Then implement** — Only after research confirms the approach is sound

### Example workflow

```
# User asks: "add push notifications with Firebase"
# Step 1: Search
creep search "Flutter Firebase push notifications 2026 best practices" -n 3

# Step 2: Scrape the official docs
creep scrape "https://firebase.google.com/docs/cloud-messaging/flutter/client"

# Step 3: Check for issues
creep search "flutter firebase messaging known issues 2026" -n 3

# Step 4: Implement with confidence
```

### When to use creep

- Adding a new dependency or plugin
- Fixing a cryptic error or warning
- Implementing a pattern you haven't seen in this codebase
- Upgrading dependencies
- Configuring build tools (Gradle, Xcode, etc.)
- Anything involving Android/iOS native configuration
- Pulling updated research on how to do something

### When you can skip creep

- Editing existing code that you've already read and understood
- Simple bug fixes with clear error messages
- Styling/UI changes using existing app theme tokens
- Following patterns already established in the codebase

## Codebase Context

- **Stack**: Flutter + Supabase + shadcn_ui
- **State**: Riverpod 3.x. Most feature state uses `ChangeNotifierProvider`
  (legacy import) wrapping `ChangeNotifier` classes; newer code uses Riverpod
  code generation (`@riverpod`, `*.g.dart`).
- **Storage**: Supabase (Postgres/Auth) + Cloudflare R2 (media, via API proxy)
- **Cache**: Hive (offline-first product feed) + SharedPreferences (prefs)
- **Platform**: Android & iOS

> For a full architecture and conventions guide, see **ARCHITECTURE.md**.
