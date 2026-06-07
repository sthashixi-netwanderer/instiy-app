---
name: multi-project-navigation
description: When user request doesn't match current repo's purpose, check sibling directories for the correct project before proceeding with implementation.
source: auto-skill
extracted_at: '2026-05-31T15:53:32.653Z'
---

# Multi-Project Navigation

## When to apply
When the user describes features (e.g., "product cards", "Add to Cart", "checkout screen") that don't exist in the current working directory, and the project appears to be something else (e.g., an admin panel, API server, or library).

## Why
Users often work across multiple related projects (e.g., `instiy-admin` + `instiy` Flutter app) and may start a conversation in the wrong directory. Wasting time exploring the wrong codebase is avoidable.

## How to apply
1. After thorough exploration of the current project confirms the requested features don't exist, **list the parent directory** to check for sibling projects.
2. Look for telltale signs of the right project: `pubspec.yaml` (Flutter), `package.json` with relevant deps, `lib/screens/`, `src/pages/`, etc.
3. **Ask the user** to confirm which project they mean rather than silently switching — they may have a reason for the current directory.
4. Once the correct project is identified, proceed with exploration and planning there.

## Example
- Current dir: `instiy-admin/` (admin dashboard, no product cards)
- User asks: "Replace Add to Cart with Buy button on product cards"
- Action: List `../` → find `instiy/` (Flutter app with `lib/screens/explore/`, product cards, cart) → ask user to confirm → proceed there.
