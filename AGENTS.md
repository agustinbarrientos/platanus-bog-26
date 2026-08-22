# Project instructions

## Foundation

- Use Node.js 24.x and npm.
- Keep `package-lock.json` authoritative and use `npm ci` for clean installs.
- Use Next.js App Router, strict TypeScript, Tailwind CSS, and shadcn/ui.
- Keep web application code under `apps/web/src/` and imports on the `@/*` alias.
- Keep custom web project types in `apps/web/src/types.ts`.

## Implementation

- Prefer Server Components in the web application and add client boundaries only for browser behavior.
- Keep components focused and use the existing UI primitives before adding dependencies.
- Avoid speculative routes, services, state libraries, infrastructure, and configuration.
- Keep comments concise and do not split a sentence across comment lines.
- Do not add authorship metadata or metacomments.

## Validation

- Run `npm run check` after code changes.
- Run `npm run build` before handoff.
- Do not stage, commit, push, deploy, or modify external services unless explicitly requested.
- Do not read, print, or expose secrets.

## Project context

- The approved design is in `docs/superpowers/specs/2026-08-21-hackathon-boilerplate-design.md`.
- The implementation plan is in `docs/superpowers/plans/2026-08-21-hackathon-boilerplate.md`.
