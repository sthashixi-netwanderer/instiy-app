# Instiy — Project Instructions

## Codebase Context

- **Stack**: Flutter + Supabase + shadcn_ui
- **State**: Provider (ChangeNotifier)
- **Storage**: Supabase + Cloudflare R2
- **Platform**: Android & iOS
- **Description**: Student marketplace for buying and selling products

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

---

## Code-Review-Graph — Mandatory Session Workflow

The code knowledge graph (`.code-review-graph/graph.db`) is the **primary entry point** for understanding the project structure. It indexes all files, functions, classes, imports, and call relationships using Tree-sitter. Never start a session or make changes without it.

### Step 1: Session Start — Read the Structure

**At the beginning of EVERY session, before reading any source files, query the graph to understand the codebase.**

Run these MCP tools in order:

1. **Refresh the graph** — Call `mcp__code-review-graph__build_or_update_graph_tool` with defaults (`full_rebuild=false`). This ensures the graph reflects the latest code state (incremental, ~2 seconds).

2. **Get the architecture overview** — Call `mcp__code-review-graph__get_architecture_overview_tool`. This returns the high-level module structure, community clusters, and coupling warnings. Use it to orient yourself before diving into any specific file.

3. **List communities** — Call `mcp__code-review-graph__list_communities_tool`. Each community is a cluster of tightly related functions/classes — essentially the logical "features" or "modules" of the app. Use this to know which files to read.

4. **List execution flows** — Call `mcp__code-review-graph__list_flows_tool`. These are the runtime paths through the codebase (entry points → call chains), sorted by criticality. Use this to understand how the app actually works.

5. **Search for relevant code** — Use `mcp__code-review-graph__semantic_search_nodes_tool` to find specific features, screens, or services before reading files. For example:
   - `semantic_search_nodes_tool(query="authentication login")` to find auth-related code
   - `semantic_search_nodes_tool(query="product listing marketplace")` to find marketplace features

**Why this matters**: The graph gives you a structural map of the entire codebase in seconds. Reading files blindly wastes tokens and misses cross-file relationships. The graph tells you exactly which files to read and why they matter.

### Step 2: Use the Graph During Work

While working, use these tools to stay oriented:

| Task | Tool | Purpose |
|------|------|---------|
| Understand a file | `query_graph_tool(pattern="file_summary", target="lib/screens/login.dart")` | Get all functions/classes in a file |
| Find callers | `query_graph_tool(pattern="callers_of", target="login")` | Who uses this function? |
| Find callees | `query_graph_tool(pattern="callees_of", target="submitOrder")` | What does this function call? |
| Check imports | `query_graph_tool(pattern="imports_of", target="lib/screens/cart.dart")` | What does this file depend on? |
| Find tests | `query_graph_tool(pattern="tests_for", target="AuthService")` | Are there tests for this? |
| Blast radius | `mcp__code-review-graph__get_impact_radius_tool(files=["lib/models/product.dart"])` | What breaks if I change this file? |
| Find dead code | `mcp__code-review-graph__refactor_tool(operation="dead_code")` | What's unreferenced? |
| Deep traversal | `mcp__code-review-graph__traverse_graph_tool(start="AuthService", direction="forward")` | Walk the call graph from any node |

### Step 3: Post-Update Refresh — Keep the Graph Current

**After ANY code change (edits, additions, deletions), you MUST update the graph.** This is non-negotiable.

#### Procedure

1. **Incremental update** — Call `mcp__code-review-graph__build_or_update_graph_tool` with defaults (`full_rebuild=false`, `postprocess="full"`). This re-parses only changed files and runs community detection, flow detection, and FTS indexing.

2. **If incremental fails or the graph is stale** — Call `mcp__code-review-graph__build_or_update_graph_tool` with `full_rebuild=true` to re-parse everything from scratch.

3. **Verify** — Check the response for `total_nodes`, `total_edges`, `warnings`. If warnings are present, investigate before proceeding.

#### When to run the post-update refresh

- After every batch of file edits
- After adding or removing dependencies (`pubspec.yaml` changes)
- After refactoring across multiple files
- After merging or rebasing branches
- Before running any graph-based analysis (impact radius, affected flows, etc.)

#### What NOT to do

- Do not skip the graph update because "it was a small change"
- Do not assume the graph auto-updates — it does not (unless `crg-daemon` is running)
- Do not run a full rebuild unless incremental fails — it's slower and unnecessary

### Graph Tool Quick Reference

| MCP Tool | When to Use |
|----------|-------------|
| `build_or_update_graph_tool` | Session start + after every code change |
| `get_architecture_overview_tool` | Session start, understanding module boundaries |
| `list_communities_tool` | Session start, finding logical feature clusters |
| `list_flows_tool` | Session start, understanding runtime paths |
| `semantic_search_nodes_tool` | Finding code by name or meaning before reading files |
| `get_minimal_context_tool` | Quick ~100 token snapshot for any task |
| `query_graph_tool` | Structural queries (callers, callees, imports, tests) |
| `get_impact_radius_tool` | Blast radius before changing a file |
| `get_review_context_tool` | Token-optimised context for code review |
| `detect_changes_tool` | Risk-scored change impact analysis |
| `refactor_tool` | Rename preview, dead code detection |
| `get_hub_nodes_tool` | Find architectural hotspots (most connected nodes) |
| `get_bridge_nodes_tool` | Find chokepoints (single points of failure) |
| `get_knowledge_gaps_tool` | Find untested or under-documented areas |
| `find_large_functions_tool` | Find functions exceeding line-count thresholds |
| `generate_wiki_tool` | Auto-generate markdown wiki from communities |
