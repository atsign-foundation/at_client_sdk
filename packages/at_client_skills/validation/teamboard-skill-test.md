# Skill validation — TeamBoard end-to-end test

**Audience:** maintainers of `at_client_skills`. This is a regression test for the
skill, not user documentation. It is excluded from the published package
(see [`.pubignore`](../.pubignore)).

**Goal:** prove the skill is sufficient on its own. We have an AI agent build a
deliberately comprehensive app using **only** the installed skill — the same way
a real developer would in production. If the agent can build the app
start-to-finish with no errors, the skill works. Any failure is a skill gap to
fix (file an issue and patch the skill / its references).

---

## 1. Stand up the harness (agent-agnostic)

The point is to reproduce a real consumer environment where the agent's **only**
atSign knowledge is the installed skill. Two rules make the test honest:

- **Build outside this monorepo.** If the test project sits inside
  `at_client_sdk/`, the agent can read `packages/at_client/lib/...` and learn the
  API from source instead of the skill — a false pass. Use a fresh directory
  somewhere else (e.g. a temp dir or `~/`).
- **Only `at_client_skills` is local.** Pull `at_client` / `at_client_flutter` as
  normal published pub dependencies (a real consumer would). The skill package is
  a **local path dev-dependency** so you can iterate on it without publishing.

```sh
# 1. Fresh app, OUTSIDE the monorepo
cd ~                       # anywhere that is not inside at_client_sdk/
flutter create teamboard_skill_test
cd teamboard_skill_test

# 2. Published runtime deps + the skills CLI — the regular pub command,
#    exactly as a real consumer would.
dart pub add at_client_flutter at_auth path_provider
dart pub add dev:skills
```

Step 3 — add the skill from your **local** checkout as a path dev-dependency.
The inline `dart pub add "pkg:{path: …}"` form is brittle, so edit
`pubspec.yaml` directly and use a **relative** path to your `at_client_sdk`
checkout:

```yaml
dev_dependencies:
  # … (skills, test, etc.)
  at_client_skills:
    path: ../path/to/at_client_sdk/packages/at_client_skills   # RELATIVE path
```

> Tell the agent to compute the relative path from this test app to your
> `at_client_sdk` checkout. If you're also validating unreleased `at_client` /
> `at_client_flutter` changes, wire those as relative path deps the same way;
> otherwise leave them as the published deps from step 2 to mirror a real
> consumer.

```sh
# 4. Resolve deps, then install the skill into the IDE skills dir
#    (.claude/skills, .cursor/skills, …)
dart pub get
dart run skills get --ide claude    # or cursor, cline, copilot, opencode, generic
```

`--ide` is required here: a freshly created project has no agent directory yet,
and the CLI auto-detects only by finding one that already exists, so a bare
`dart run skills get` stops with *"Could not auto-detect IDE"*.

After step 4, confirm the skill installed (it must — the dir name
`at_client_skills-sdk` matches the `at_client_skills-` prefix the CLI requires):

```sh
ls .claude/skills/            # or .cursor/skills/, etc. for your agent
# expect: at_client_skills-sdk/
```

**Iterate loop:** edit the skill in the monorepo → re-run `dart run skills get`
→ re-test. No publish, ever.

**Run the test:** open `teamboard_skill_test/` in your agent with a **clean
session** (no extra atSign context, no hints) and paste the prompt in §2.

---

## 2. The build prompt

> Build a cross-platform **shared task-board app** called **TeamBoard** using
> Flutter. It must run on iOS, Android, **and macOS desktop**. Take it from this
> empty project all the way to a running, tested app.
>
> Requirements:
>
> 1. **Accounts & sign-in.** Each user signs into their own account on the
>    device. Support signing in on a brand-new account, signing in by importing
>    an existing credentials file from disk, and fast re-login for a returning
>    user on the same device. Include a sign-out option.
> 2. **Hierarchy.** A user has multiple **Boards**; each Board has multiple
>    **Lists**; each List has multiple **Cards**; each Card can have **checklist
>    items**. The UI lets you drill down through this hierarchy and back up.
> 3. **Card details.** Each Card has a title, description, priority
>    (low/med/high), a due date, and tags.
> 4. **Sharing & collaboration.** A user can share a Board with another user by
>    their account identifier; the other person sees the shared Board appear and
>    can edit Cards on it. The owner can also **un-share** a Board (remove a
>    collaborator) — the removed user no longer sees it.
> 5. **Real-time updates.** When a collaborator changes a Card, the change shows
>    up on the other person's screen automatically without a manual refresh.
> 6. **Seen indicators.** When a collaborator opens/views a Card you shared, you
>    see a "seen by" indicator on that Card.
> 7. **Filtering & search.** On a Board, filter Cards by priority, by tag, by
>    due-date range, and by whether they're done — and combine filters.
> 8. **Offline-friendly.** The app works and shows local data with no network,
>    and reconciles when back online.
> 9. **Tests.** Write unit tests for the data layer that run in CI without any
>    live backend/server.
> 10. **Public profile.** Each user publishes a small profile — display name and
>    initials — that **anyone** can read from their account identifier alone,
>    without that user having shared anything with them first. Use it to show
>    collaborator names on Cards, including for someone who has not yet
>    accepted a share.
> 11. **Assignment receipts.** Assigning a Card to a collaborator alerts them.
>    The assigner's UI must show whether that alert actually reached the other
>    account, and must distinguish "hasn't got there yet" from "this failed and
>    never will". Give up after a sensible interval rather than waiting forever.
> 12. **A second device.** A user already signed in on one device can add a
>    second device to the **same** account, authorising it from the first
>    device. The second device gets access only to this app's data, not to
>    everything on the account. Handle the case where the user closes the app
>    while an authorisation is still awaiting approval and reopens it later.
> 13. **Ask the owner directly.** A "refresh from owner" action on a shared
>    Board asks the owner's device for its current view of the Board and waits
>    for the answer, rather than sending a message and hoping. It must behave
>    sensibly when the owner's device is offline.
> 14. **Clean shutdown.** Signing out, switching account and quitting the app
>    must all finish promptly and leave nothing half-done: no writes silently
>    lost, and the process actually exits. A deliberate shutdown must not
>    produce error-level log entries — quitting the app is not a failure.
> 15. **No double-processing.** Restarting the app must not re-apply an
>    assignment alert it already handled. Assume the alert delivery can repeat
>    and make the handling safe under that assumption.
> 16. **Diagnostics.** When something does fail, the log must carry the full
>    causal chain of the failure, not just the outermost one-line message.
>
> Build it end-to-end, then **actually run it on macOS desktop** and walk
> through: create account → create a Board/List/Card → share it → see the
> collaborator's public name → assign a Card and watch the receipt resolve →
> refresh from owner → un-share it → filter → add a second device and approve
> it from the first → sign out and back in → quit the app. Fix any build or
> runtime errors you hit so it runs cleanly start to finish.

After everything is built, paste this follow-up prompt:

> Create a report summarizing your findings. If any bug was due to the
> `at_client_skills-sdk` skill not documenting the correct way to do something,
> identify the gap in the skill that should be fixed. Separately, list every
> SDK API you used that the skill marks as deprecated, and say what you used
> it for — if the skill steered you to a deprecated API, that is itself a gap.
> Finally, paste the log from the clean-shutdown walkthrough and say whether
> anything a deliberate shutdown caused was logged at error level.

---

## 3. What a clean build proves (coverage)

| Prompt requirement                          | SDK surface exercised                                                      |
| ------------------------------------------- | -------------------------------------------------------------------------- |
| Sign-in / import file / re-login / sign-out | all auth flows — **macOS file picker hits the entitlement step**           |
| Boards → Lists → Cards → checklist          | sub-collections, `watchWithTree` deep hierarchies                          |
| Share a board; collaborator edits           | sharing items + `NotificationService`                                      |
| Un-share a board (remove a collaborator)    | `updateSharedWith` recipient removal (the unshare path)                    |
| Real-time updates                           | event streams / `watch()`                                                  |
| "Seen by" indicator                         | read receipts                                                              |
| Filter by priority / tag / date / done      | `Query<T>`, `wherePath` typed predicates                                   |
| Card fields (priority, due, tags)           | richer domain objects (`AtCollection<T>` / `CItem<T>`, `toJson`/`typeTag`) |
| Offline + reconcile                         | local store + sync behavior                                                |
| Tests without live server                   | unit-testing-without-atServer guidance (`collections_test_hooks.dart`)     |
| "run on macOS desktop"                      | guarantees the desktop entitlement path is exercised                       |
| Public profile readable by anyone           | public keys — `AtKey.public`, signed-not-encrypted values, `plookup`      |
| Assignment receipt, delivered vs failed     | `send()` id → `getStatus` / `fetch`, the two-value enum, expiration window |
| Second device authorised from the first     | APKAM enrolment — the passcode, approving, least-privilege namespaces, resuming a pending enrolment |
| "Ask the owner directly" and wait           | RPC — `AtRpcClient` / `AtRpc.server`, callbacks, offline responder        |
| Clean shutdown, nothing half-done           | `stop()` semantics, waiting for sync to settle before it, process exit    |
| Shutdown not logged as an error             | `StoppedException` and catching it by type rather than as a failure       |
| Restart does not re-apply an alert          | at-least-once notification delivery, idempotent handlers                  |
| Full causal chain in failure logs           | `getTraceMessage()` and the exception families                            |

**Deliberately not covered:** NoPorts access control. The skill holds only a
pointer to `noports_core` for it, and a Flutter task board has no tunnel to
authorise — a TeamBoard run cannot exercise it either way. Check that section
by review, not by this test.

---

## 4. Recording gaps

Every error the agent hits — or workaround it invents that the skill should have
told it — is a skill gap. For each:

1. Note the failing step and the exact error.
2. Decide whether the fix belongs in `SKILL.md` or a `references/*.md` file.
3. File an issue (or patch directly) and re-run this validation to confirm.

A pass = the agent builds and runs TeamBoard on macOS with no errors, using only
the skill.
