# Project Instructions

## Stack
- **Frontend**: Flutter + shadcn_ui
- **State**: Provider (ChangeNotifier) + Riverpod (gradual migration)
- **Backend**: Supabase (Postgres, Auth, Realtime, Storage)
- **Storage**: Supabase + Cloudflare R2
- **Platform**: Android & iOS

## Coding Workflow

### 1. Plan Mode First
- Use plan mode for any non-trivial task
- Write detailed specs up front, reduce ambiguity
- Lightweight inline plan for smaller tasks

### 2. Research Before Implementing
Before adding ANY new dependency, library, or pattern:
1. `creep search` for docs, best practices, known issues
2. `creep scrape` the most relevant result
3. Evaluate: right approach? alternatives? breaking changes? version compat?
4. Only implement after research confirms the approach

Skip research for: editing already-read code, simple bug fixes, styling with existing tokens, following established patterns.

### 3. Surgical Edits Only
- Change only what's necessary — no unrelated code or comments
- Don't "improve" things that aren't broken
- Minimize side effects and churn
- Prefer 100 lines over 1000

### 4. Code Review Graph (After Every Implementation)
After completing ANY implementation, run this verification pipeline:

```
IMPLEMENTATION
    │
    ▼
┌─────────────┐
│ Build Check │ ← flutter analyze, no issues
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│ Type Safety     │ ← All types correct, no runtime casts
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│ Edge Cases      │ ← Null checks, empty lists, loading states
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│ State Mgmt      │ ← notifyListeners in correct places, no dispose leaks
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│ UI Overflow     │ ← Layout handles all screen sizes, no RenderFlex overflow
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│ Realtime Sync   │ ← Supabase Realtime subscriptions for live data
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│ Memory Leaks    │ ← Controllers disposed, channels unsubscribed
└──────┬──────────┘
       │
       ▼
    PASS ✓
```

**Rules:**
- Never report completion until ALL nodes pass
- If any node fails, fix and re-run from that node
- For multi-file changes, run graph once per affected screen/feature
- Log failures for debugging

### 5. Parallelize with Subagents
- Offload research, exploration, analysis to subagents
- One task per subagent for focus
- Merge results back with judgment

## Core Principles

- **Simplicity First**: Minimal code that solves the problem. Nothing speculative.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Only touch what's necessary. No side effects. No new bugs.
- **No Overengineering**: No bloated abstractions, no speculative features, no premature optimization.

## Engineer Mindset

- **Tenacity** — Agents never get tired. Relentless iteration beats giving up.
- **Leverage** — Give success criteria and watch it go. Imperative → Declarative.
- **Fun** — Remove drudgery, focus on creativity. More courage, less blocking.
- **Atrophy** — Writing and reading code are different. Stay sharp intentionally.
- **Slopocalypse** — Brace for AI slop. Hype will be loud. Signal requires judgment.

## Key Patterns

### Provider Constructor
Never call `notifyListeners()` in constructor. Use `Future.microtask` + `ensureInitialized` pattern.

### Build-Safe Callbacks
Never call `notifyListeners` in `itemBuilder`. Wrap in `addPostFrameCallback`.

### Safe Provider Cleanup
`notifyListeners()` in `dispose` crashes. Use non-notifying dispose variants + cache refs in `initState`.

### Supabase RPC Parsing
RPCs return flat columns, not nested objects — need separate `fromRpcJson` factories.

### Realtime Everywhere
All screens must auto-refresh via Supabase Realtime subscriptions.

### No Silent Error Swallowing
Background/fire-and-forget tasks must surface errors to user, not just `debugPrint`.

### Filled Rating Stars
Use `Icons.star` / `Icons.star_border` for ratings, not `LucideIcons.star` (outline).

### Review Reply Table
Seller replies go to `product_review_replies` table via `SellerService`, not `product_reviews` via `ReviewService`.
