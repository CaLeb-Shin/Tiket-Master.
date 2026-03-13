# Ralph Agent Instructions - Melon Ticket

You are an autonomous coding agent working on the Melon Ticket (멜론티켓) project.

## Project Context

- **Monorepo**: `melon_core/`, `melon_admin/`, `melon_ticket_app/`
- **Stack**: Flutter 3.41.1 (Dart 3.11.0) + Firebase (Firestore, Storage, Cloud Functions)
- **State**: Riverpod, **Routing**: GoRouter
- **Theme**: Dark (#0B0B0F) + Gold (#C9A84C) via AppTheme
- **Admin**: shadcn_flutter 0.0.51 (import as `shad`), AdminTheme
- **Grade Order**: Always VIP > R > S > A (display, sort, price everywhere)
- **Firebase Project**: `melon-ticket-mvp-2026`
- **Ticket App Deploy**: Vercel (git push auto-deploy)
- **Admin App Deploy**: Firebase Hosting (`firebase deploy --only hosting:admin`)

## Your Task

1. Read the PRD at `scripts/ralph/prd.json`
2. Read the progress log at `scripts/ralph/progress.txt` (check Codebase Patterns section first)
3. Check you're on the correct branch from PRD `branchName`. If not, check it out or create from main.
4. Pick the **highest priority** user story where `passes: false`
5. Implement that single user story
6. Run quality checks:
   - `cd melon_ticket_app && flutter analyze` (for ticket app changes)
   - `cd melon_admin && flutter analyze` (for admin app changes)
   - `cd melon_ticket_app/functions && npm run build` (for Cloud Functions changes)
7. If checks pass, commit ALL changes with message: `feat: [Story ID] - [Story Title]`
8. Push to remote: `git push`
9. Deploy if needed:
   - Ticket app: auto-deployed by Vercel on git push
   - Admin app: `firebase deploy --only hosting:admin`
   - Cloud Functions: `cd melon_ticket_app/functions && firebase deploy --only functions`
10. Update the PRD to set `passes: true` for the completed story
11. Append your progress to `scripts/ralph/progress.txt`

## Working Agreement For This Project

- Unless the user explicitly says to pause, stop, or review first, continue
  through the remaining `passes: false` stories in priority order without
  asking for confirmation between stories.
- Stop only when blocked by missing credentials, missing external systems,
  dangerous irreversible actions, or a high-risk product decision that cannot
  be inferred from the saved docs.
- After each completed story:
  1. Update `scripts/ralph/prd.json`
  2. Append `scripts/ralph/progress.txt`
  3. Send a short Telegram summary by running:
     `node scripts/ralph/send-telegram-summary.js [Story ID]`
  4. If code changed and verification passed, deploy by default unless the
     user explicitly asked for local-only changes
- If you update a human-readable summary/design markdown for the user,
  also send that file in Telegram-friendly form with:
  `node scripts/ralph/send-telegram-summary.js --file [path-to-md]`
- Telegram summary sending is best-effort:
  - Use `RALPH_TELEGRAM_BOT_TOKEN` / `RALPH_TELEGRAM_CHAT_ID` first
  - Fallback to `NAVER_SEAT_BOT_TOKEN` / `NAVER_SEAT_CHAT_ID`
  - If no Telegram env vars are configured, skip sending and mention the skip
    in the completion note
- If the user says "do not execute yet", store the rule changes only and do
  not start the next story in that turn.

## Key Files Reference

| Area | Key Files |
|------|-----------|
| Theme | `melon_core/lib/app/theme.dart` (AppTheme) |
| Admin Theme | `melon_admin/lib/app/admin_theme.dart` (AdminTheme) |
| Router (Admin) | `melon_admin/lib/app/router.dart` |
| Router (Ticket) | `melon_ticket_app/lib/app/router.dart` |
| Cloud Functions | `melon_ticket_app/functions/src/index.ts` |
| Seat Selection | `melon_ticket_app/lib/features/booking/seat_selection_screen.dart` |
| Checkout | `melon_ticket_app/lib/features/checkout/checkout_screen.dart` |
| Ticket Detail | `melon_ticket_app/lib/features/tickets/ticket_detail_screen.dart` |
| Scanner | `melon_ticket_app/lib/features/staff_scanner/scanner_screen.dart` |
| Models | `melon_core/lib/data/models/` (ticket.dart, seat.dart, order.dart, event.dart) |

## Progress Report Format

APPEND to `scripts/ralph/progress.txt` (never replace, always append):
```
## [Date/Time] - [Story ID]
- What was implemented
- Files changed
- **Learnings for future iterations:**
  - Patterns discovered
  - Gotchas encountered
  - Useful context
---
```

## Codebase Conventions

- Use `AppTheme.nanum()` for text styles (supports shadows by default)
- Use `AppTheme.serif()` for premium/editorial text
- Colors: `AppTheme.gold`, `AppTheme.burgundy`, `AppTheme.textPrimary`, `AppTheme.textSecondary`
- Admin uses `AdminTheme.sans()`, `AdminTheme.serif()`
- Grade colors: VIP(#C9A84C), R(#6B4FA0), S(#2D6A4F), A(#3B7DD8)
- Cloud Functions use firebase-functions v1 compat: `(data: any, context)` NOT `(request)`
- All `withOpacity()` calls should use `withValues(alpha:)` instead

## Quality Requirements

- ALL commits must pass `flutter analyze` (0 issues)
- Cloud Functions must pass `npm run build` (TypeScript compile)
- Do NOT commit broken code
- Keep changes focused and minimal
- Follow existing code patterns

## Stop Condition

After completing a user story, check if ALL stories have `passes: true`.

If ALL stories are complete and passing, reply with:
<promise>COMPLETE</promise>

If there are still stories with `passes: false`, end your response normally (another iteration will pick up the next story).

## Important

- Work on ONE story per iteration
- Commit frequently
- Always push after commit (Vercel auto-deploys)
- Deploy admin separately if admin files changed
- Deploy functions separately if functions changed
- Default to deploying verified code changes even when the user does not
  repeat the deployment request each turn
- Read the Codebase Patterns section in progress.txt before starting
