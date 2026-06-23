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

# 2. Real (published) runtime deps — as a consumer would add them
dart pub add at_client_flutter at_auth path_provider

# 3. The skill, from your local working tree (unpublished)
dart pub add --dev skills
dart pub add --dev 'at_client_skills:{"path":"/ABSOLUTE/PATH/TO/at_client_sdk/packages/at_client_skills"}'

# 4. Install the skill into the IDE skills dir (.claude/skills, .cursor/skills, …)
dart run skills get
```

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
>    their account identifier. The other person sees the shared Board appear and
>    can edit Cards on it.
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
>
> Build it end-to-end, then **actually run it on macOS desktop** and walk
> through: create account → create a Board/List/Card → share it → filter → sign
> out and back in. Fix any build or runtime errors you hit so it runs cleanly
> start to finish.

---

## 3. What a clean build proves (coverage)

| Prompt requirement | SDK surface exercised |
|---|---|
| Sign-in / import file / re-login / sign-out | all auth flows — **macOS file picker hits the entitlement step** |
| Boards → Lists → Cards → checklist | sub-collections, `watchWithTree` deep hierarchies |
| Share a board; collaborator edits | sharing items + `NotificationService` |
| Real-time updates | event streams / `watch()` |
| "Seen by" indicator | read receipts |
| Filter by priority / tag / date / done | `Query<T>`, `wherePath` typed predicates |
| Card fields (priority, due, tags) | richer domain objects (`AtCollection<T>` / `CItem<T>`, `toJson`/`typeTag`) |
| Offline + reconcile | local store + sync behavior |
| Tests without live server | unit-testing-without-atServer guidance (`collections_test_hooks.dart`) |
| "run on macOS desktop" | guarantees the desktop entitlement path is exercised |

---

## 4. Recording gaps

Every error the agent hits — or workaround it invents that the skill should have
told it — is a skill gap. For each:

1. Note the failing step and the exact error.
2. Decide whether the fix belongs in `SKILL.md` or a `references/*.md` file.
3. File an issue (or patch directly) and re-run this validation to confirm.

A pass = the agent builds and runs TeamBoard on macOS with no errors, using only
the skill.
