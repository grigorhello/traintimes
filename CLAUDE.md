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
3. Implement on a branch. Open a PR whose body starts with `Closes #N`, links the Notion card, and (for UI tickets) shows simulator screenshots next to the frame images.
4. Run **two separate review passes** on the PR:
   - **QA review:** correctness, edge cases, tests, build and CI pass, the ticket's acceptance criteria and Definition of done.
   - **Design review:** compare the result against the ticket's design frames and the requirements doc (layout, tokens, copy, states, light and dark, Dynamic Type and VoiceOver).
5. Fix the findings. If the first round found major issues, run one more round of both reviews. **Two rounds maximum**, then ship.
6. Move the Notion card to `PR review`, comment the review outcome on the issue, and leave the PR for Grigor's approval. Never merge it yourself. Grigor moves the card to `Done` when he merges.
7. Report back: Notion card status, PR link, and the outcome of each review round.

Notion Status values, in order: Backlog, Needs design, Design review, To do, In progress, PR review, Feature QA, Done.

## Code conventions

This file was started in TT-100; TT-101 (project setup) fills in this section: feature folders, views without business logic, `@Observable` view models with injected protocols, repositories returning domain types, `Sources/Design` tokens only, one time formatter, Swift 6 with zero warnings, unit + snapshot + XCUITest expectations from each issue's Definition of done.
