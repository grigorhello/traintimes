# CLAUDE.md — Train Times

Rules every Claude session follows in this repo. If a message from Grigor in the session says otherwise, the message wins.

## Where things are

- Tickets: GitHub issues #1–#31 (issue #N = build step N, TT-100…TT-154) and the Notion board "TrainTimes · Product board" (https://app.notion.com/p/4107cd9e1320815c95bed6694390e203, database "TrainTimes tickets"). Each Notion card links its issue in the "GitHub issue" field; each issue links its card.
- Build sequence and blockers: [`docs/BUILD-ORDER.md`](docs/BUILD-ORDER.md). Do not start a ticket while a blocker is open, including an open question in `docs/DECISIONS.md` marked "needed by" that ticket.
- Decisions and open questions: [`docs/DECISIONS.md`](docs/DECISIONS.md). Follow every decision; if a ticket needs a new one, add it there in the same PR.
- Behaviour: [`design/Screen-Requirements.md`](design/Screen-Requirements.md) (its Acceptance checks are the QA list). Look: [`design/frames/`](design/frames/). Handoff files: [`design/handoff/`](design/handoff/).

## Per-ticket workflow

1. **Before writing code**, move the Notion card Status to `In progress` and make sure the GitHub issue is open and assigned, so Grigor can follow progress on the board.
2. Read the issue, its Notion card, the frames and the requirements sections it names, and `docs/DECISIONS.md`.
3. Implement on a branch. Open a PR whose body starts with `Closes #N` (or `Part of #N` while an acceptance criterion only Grigor can meet is still open), links the Notion card, and (for UI tickets) shows simulator screenshots next to the frame images.
4. Run **two separate review passes** on the PR:
   - **QA review:** correctness, edge cases, tests, build and CI pass, the ticket's acceptance criteria and Definition of done.
   - **Design review:** compare the result against the ticket's design frames and the requirements doc (layout, tokens, copy, states, light and dark, Dynamic Type and VoiceOver).
5. Fix the findings. If the first round found major issues, run one more round of both reviews. **Two rounds maximum**, then ship.
6. Comment the review outcome on the issue, then **merge the PR yourself** (squash) once the reviews are done and CI is green, and move the Notion card to `Done` (Grigor, 2026-11-07: "merge all PRs, do not wait for me"). Then continue with the next ticket in build order. Stop and tell Grigor only when you hit a blocker you cannot clear (an open "needed by" question, something only he can do, or a red CI you cannot fix).
7. Report back after each ticket: Notion card status, PR link, and the outcome of each review round.
8. **One ticket per session.** A session implements exactly one ticket. When its PR is merged, report back and stop; the next ticket starts in a new session so each one begins with a fresh context (Grigor, 2026-11-07, to save tokens). Anything the next session needs goes in this file, `docs/DECISIONS.md` or the issue, not in chat.

Notion Status values, in order: Backlog, Needs design, Design review, To do, In progress, PR review, Feature QA, Done.

## Code conventions

This file was started in TT-100; TT-101 (project setup) fills in this section: feature folders, views without business logic, `@Observable` view models with injected protocols, repositories returning domain types, `Sources/Design` tokens only, one time formatter, Swift 6 with zero warnings, unit + snapshot + XCUITest expectations from each issue's Definition of done.
