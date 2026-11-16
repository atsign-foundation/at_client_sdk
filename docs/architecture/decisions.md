# Architecture decisions

A decision binds only when it has a row here; a plan, design doc or project decision record elsewhere in this repo is a proposal until then. A row is added by a PR that a code owner approves ([CODEOWNERS](../../.github/CODEOWNERS)), and names the existing mechanism that was not used, and why. The rules every decision answers to are in [invariants.md](invariants.md).

| Id | Decision in one line | Seams and invariants touched | Existing mechanism not used, and why | Project record | Accepted by, date |
|---|---|---|---|---|---|
| D-27 (proposed) | The JS collections adapter replaces the `AtEasy` facade; the J1 and J1a scope shrinks to it | The collections seam (`AtCollection`); no invariant touched | The `AtEasy` facade proposed in #2481: upstream `writeTypeTag` removes the need for its tag registry, and the rest is not a Layer B concern | [wasm/decisions.md D-27](../projects/wasm/decisions.md) | |
