## What

<!-- What does this PR do? Describe the change and the problem it solves. -->

## How

<!-- How was this implemented? Include any key decisions or trade-offs. -->

## How to verify

<!-- Steps to verify the change works as expected. -->

1. 
2. 

## Skills impact

If this PR changes a public API in `at_client`, `at_client_flutter`, or `at_auth`,
consider whether `packages/at_client_skills/` needs a follow-up release.

- [ ] No public API change — skill unaffected
- [ ] Public API changed — I have opened or will open an `at_client_skills` PR to reflect this

## Architecture

The rules are in `docs/architecture/invariants.md`. A pin move goes in a PR of
its own, ahead of the change that needs it, and needs a code owner's review.

- [ ] `dart test test/architecture` passes in `packages/at_client`, and this PR moves no pin
- [ ] This PR is a pin move. Invariant: … Existing mechanism I could not use, and why: … Row in `docs/architecture/decisions.md`: …
