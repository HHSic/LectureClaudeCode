# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# First-time setup
npm run setup          # installs deps + generates Prisma client + runs migrations

# Development
npm run dev            # starts Next.js with Turbopack (requires node-compat.cjs polyfill)
npm run dev:daemon     # same but runs in background, logs to logs.txt

# Build & start
npm run build
npm run start

# Lint
npm run lint

# Test
npm test               # run all tests with vitest
npm test -- src/lib/transform/__tests__/jsx-transformer.test.ts  # run single test file

# Database
npm run db:reset       # reset and re-run all migrations (destructive)
npx prisma generate    # regenerate Prisma client after schema changes
npx prisma migrate dev # apply new migrations
```

The `NODE_OPTIONS='--require ./node-compat.cjs'` prefix is needed for all Next.js commands due to Windows/Node.js compatibility. It's already embedded in the npm scripts.

## Code Style

Use comments sparingly. Only comment complex or non-obvious code.

## Architecture

### Overview
UIGen is an AI-powered React component generator. Users describe components in a chat interface; Claude generates JSX/TSX files into an in-memory virtual file system, and the result is live-previewed in an iframe — no files are ever written to disk.

### Key Data Flow
1. **Chat** → `POST /api/chat` sends messages + serialized VFS state
2. **API route** (`src/app/api/chat/route.ts`) streams Claude's response using Vercel AI SDK's `streamText`
3. Claude calls two tools: `str_replace_editor` (create/edit files) and `file_manager` (rename/delete)
4. Tool calls are returned in the stream and processed by `FileSystemContext.handleToolCall`
5. The `VirtualFileSystem` is updated in-memory; `refreshTrigger` increments
6. `PreviewFrame` picks up the trigger, calls `createImportMap` (which Babel-transforms files into blob URLs), and sets `iframe.srcdoc`

### Virtual File System (`src/lib/file-system.ts`)
`VirtualFileSystem` is a tree-structured in-memory FS. It supports create/read/update/delete/rename with automatic parent directory creation. Serializes to/from plain `Record<string, FileNode>` for JSON storage in SQLite and API transport.

### Preview Pipeline (`src/lib/transform/jsx-transformer.ts`)
- `transformJSX`: Babel-transforms JSX/TSX to plain JS (removes CSS imports, handles TS)
- `createImportMap`: Transforms all VFS files, creates blob URLs, builds an ES module import map. Third-party packages resolve to `https://esm.sh/<pkg>`. Missing local imports get placeholder stub modules.
- `createPreviewHTML`: Injects the import map into an HTML document with Tailwind CDN, renders into `<div id="root">`. Syntax errors are displayed inline instead of crashing.

### State Management
Two React contexts wrapping the whole app (`src/app/main-content.tsx`):
- `FileSystemProvider` (`src/lib/contexts/file-system-context.tsx`): holds the `VirtualFileSystem` instance, exposes file operations and `handleToolCall` dispatcher
- `ChatProvider` (`src/lib/contexts/chat-context.tsx`): Vercel AI SDK's `useChat` hook, wired to `/api/chat` with the serialized VFS state

### Auth
Custom JWT auth (no NextAuth). `src/lib/auth.ts` creates/verifies sessions stored as `httpOnly` cookies using `jose`. Passwords hashed with `bcrypt`. The middleware at `src/middleware.ts` protects routes. Anonymous use is supported for the home page; project persistence requires auth.

### Database
Prisma with SQLite (`prisma/dev.db`). The schema is defined in `prisma/schema.prisma` — reference it whenever you need to understand the structure of data stored in the database.

Generated Prisma client outputs to `src/generated/prisma`.

### AI Provider (`src/lib/provider.ts`)
`getLanguageModel()` returns the real Anthropic model (`claude-haiku-4-5`) when `ANTHROPIC_API_KEY` is set, or a `MockLanguageModel` that produces static counter/form/card components. The mock is useful for development without an API key.

### UI Layout
`MainContent` is a two-panel resizable layout:
- Left (35%): `ChatInterface`
- Right (65%): tab-switched between `PreviewFrame` and a code view (`FileTree` + `CodeEditor` via Monaco)

### Path Conventions
- VFS paths always start with `/` (e.g., `/App.jsx`, `/components/Button.tsx`)
- `@/` alias in generated component imports maps to VFS root `/`
- Preview entry point detection order: `/App.jsx` → `/App.tsx` → `/index.jsx` → `/index.tsx` → `/src/App.jsx` → first `.jsx`/`.tsx` found
