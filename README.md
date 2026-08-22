# Hackathon Starter

A thin Next.js foundation for moving from an idea to a working web product without committing to product-specific infrastructure too early.

## Included

- Next.js App Router and strict TypeScript
- Tailwind CSS
- shadcn/ui with Base UI and neutral CSS-variable tokens
- Persistent light, dark, and system themes
- Local lint, type-check, and production-build commands
- Automatic Vercel deployments through the connected Git repository

Authentication, databases, tests, CI, analytics, and state libraries are intentionally absent. Add them only when the product needs them.

## Requirements

- Node.js 24.x
- npm 11.x

If a Node version manager reads `.nvmrc`:

```bash
nvm use
```

## Setup

```bash
npm ci
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Commands

| Command | Purpose |
| --- | --- |
| `npm run dev` | Start the Turbopack development server |
| `npm run lint` | Run ESLint |
| `npm run lint:fix` | Apply ESLint automatic fixes |
| `npm run typecheck` | Run TypeScript without emitting files |
| `npm run check` | Run linting and type-checking |
| `npm run build` | Create the production build |
| `npm run start` | Serve the production build |

## Structure

```text
src/
  app/
    error.tsx
    globals.css
    layout.tsx
    not-found.tsx
    page.tsx
  components/
    theme-provider.tsx
    theme-toggle.tsx
    ui/
  lib/
    utils.ts
  types.ts
```

Replace `src/app/page.tsx` when the product direction is known. Keep Server Components as the default and add client boundaries only for browser state or browser APIs. Keep custom project types in `src/types.ts`.

## UI foundation

The initial shadcn set is limited to Button, Badge, Card, and Dropdown Menu. Add a component only when a real interface requires it:

```bash
npx shadcn@latest add dialog
```

Theme tokens live in `src/app/globals.css`. Theme selection is provided by `src/components/theme-toggle.tsx` and follows the system preference until a visitor chooses light or dark.

## Validation

Before a demo or handoff:

```bash
npm run check
npm run build
```

Add automated tests when the product introduces behavior with meaningful regression risk.

## Deployment

The Vercel project is already connected to `agustinbarrientos/platanus-bog-26`.

- A push to a non-production branch creates a preview deployment.
- A push or merge to `main` creates a production deployment.

No Vercel CLI setup or `vercel.json` file is required.
