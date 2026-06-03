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
update the agent skill at `.agents/skills/atsign-dart-sdk/` in the same PR.

- [ ] I have updated `.agents/skills/atsign-dart-sdk/` to reflect this change
- [ ] **or** I am adding the `skill-ok` label — this change does not affect
  documented API behaviour (refactor, test, internal fix, etc.)

> The `skill-staleness-check` CI job enforces this. It passes automatically
> when public API paths are not touched.
