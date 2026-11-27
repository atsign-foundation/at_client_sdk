# When the SDK Falls Short

What to do when the app needs something the SDK does not give it: a type the
platform package does not export, a call that throws where the docs say it
works, behaviour that contradicts the docs. Work through the steps in order,
and tell the developer what you found at each one.

---

## 1. Confirm it is a gap

Look for a supported way first: in this skill, the app's platform skill, and
what the platform package exports. Most "missing" things are there under
another name, or are reached another way — an app that wants `at_auth` for
`RegistrarService` finds it re-exported by its platform package.

It is a gap when no supported way exists. Decide whose it is:

- **The SDK's** — a package does not do what its own docs or API promise, or
  an app cannot do something ordinary without importing a package from under
  its platform package.
- **The skill's** — the SDK behaves correctly and the skill said otherwise.
  The package is then `at_client_skills`.

## 2. Search the issues, open and closed

```sh
gh issue list --repo atsign-foundation/at_client_sdk --state all --search "<terms>"
```

or search <https://github.com/atsign-foundation/at_client_sdk/issues>.

- **An open issue** covers it: point the developer to it rather than filing a
  duplicate, and offer to add a comment if they have something new, such as a
  smaller reproduction.
- **A closed issue** may be fixed only in the repo, not yet in a version on
  pub.dev. To tell, open the PR that closed it and compare its merge date
  with the package's release dates and CHANGELOG on pub.dev. If a published
  version has the fix, upgrade: `dart pub upgrade <package>`. Otherwise keep
  the workaround (step 3), and link the closed issue in its comment.

Don't switch the app to a git or path dependency, a `dependency_overrides`
entry, or a prerelease to get a fix, and never pin a package back to an older
major. If a prerelease is the only version with the fix, tell the developer
it exists and what it risks — it carries every unfinished change since the
last release, and can change before it is final — and let them choose.

## 3. The smallest workaround

When the gap is a type the platform package does not export, depend on the
package that has it, with no version, and import only that type from the
library that declares it:

```sh
dart pub add <package>
```

```dart
// Workaround for SDK gap <issue link>: remove when the platform package provides X.
import 'package:<package>/<library>.dart' show X;
```

That is rarely the package's main library: the platform packages already
re-export at_client, and at_client re-exports all of `at_commons.dart`. A
missing at_commons type therefore lives in one of its other libraries, such
as `package:at_commons/at_builders.dart`.

Keep the workaround to that one import, so it is easy to find and remove.

When the fix needs a change inside the SDK itself, there is no safe
workaround. Say so, and offer the developer another way to build the feature.

## 4. Draft the issue

A defect is a bug report; a capability the SDK lacks is a feature request.
Draft it for the developer, and file it only if they agree.

**Bug report** —
<https://github.com/atsign-foundation/at_client_sdk/issues/new?template=bug_report.yaml>.
Fill in each field for the developer to paste:

<!-- pyml disable-num-lines 9 md013-->
| Field | What goes in it |
| --- | --- |
| Package | One of `at_client_flutter`, `at_client_cli`, `at_client`, `at_auth`, `at_commons`, `at_chops`, `at_lookup`, `at_client_skills`, `other` |
| Package version | The resolved version, from `pubspec.lock` or `dart pub deps` |
| Platform | `Flutter iOS`, `Flutter Android`, `Flutter macOS`, `Flutter Windows`, `Flutter Linux` or `Dart CLI / server` |
| What happened | What the SDK did, with any exception and its message |
| What you expected | What the docs or the API led the developer to expect |
| Steps to reproduce | The smallest code that shows it |
| Logs | Relevant output, with keys, secrets and personal data removed |

**Feature request** —
<https://github.com/atsign-foundation/at_client_sdk/issues/new?template=feature_request.yml>:
the problem, the solution the developer would like, and the alternatives
considered, naming the package.

If the developer agrees, file it with `gh`, writing each field as a
`### <field>` heading, as the form would:

```sh
gh issue create --repo atsign-foundation/at_client_sdk --label bug \
  --title "<package>: <one-line summary>" --body-file issue.md
```

## 5. Tell the developer

Say that it is a workaround, why it is needed, and when to remove it: when
the issue is fixed in a published version of the platform package.
