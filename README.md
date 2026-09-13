<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![GitHub License](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/atsign-foundation/at_client_sdk/badge)](https://securityscorecards.dev/viewer/?uri=github.com/atsign-foundation/at_client_sdk&sort_by=check-score&sort_direction=desc)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/8098/badge)](https://www.bestpractices.dev/projects/8098)

# at_client_sdk

The main repository for libraries used to build applications on the
Atsign Platform. Three categories: SDKs, libraries, and Flutter
widgets.

## SDKs

[![Build Status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml)

- [at_client](./packages/at_client): the platform-neutral Dart SDK,
  for command-line apps, headless services, and Internet-of-Things
  devices. Owns the whole atSign lifecycle — `Atsign('@alice').open`,
  `.activate` and `.enroll` hand back an `AtClient` — as well as
  collections, sync, notifications and encryption.
- [at_client_flutter](./packages/at_client_flutter): the Flutter
  layer on top of `at_client`, for mobile and desktop apps.
  Adds onboarding / authentication dialogs and device-keychain
  storage. Flutter web is not a supported target.

## Libraries

[![Build Status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_libraries.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_libraries.yaml)

Dart libraries for building Atsign Platform applications. All are
published on
[pub.dev](https://pub.dev/publishers/atsign.org/packages).

- [at_auth](./packages/at_auth): the protocol layer under
  `at_client`'s lifecycle verbs: CRAM activation, the APKAM
  enrollment handshakes, the `.atKeys` key stores and the registrar
  client. Applications reach it through `at_client`.
- [at_chops](./packages/at_chops): cryptographic and hashing
  operations (encryption, decryption, signing, hashing) used by the
  rest of the SDK, including the post-quantum primitives.
- [at_cli_commons](./packages/at_cli_commons): helpers for Dart CLI
  / server programs that use `at_client`. Wraps the boilerplate of
  parsing flags, loading keys, and producing an authenticated
  `AtClient`.
- [at_commons](./packages/at_commons): foundational types used
  across every package: keys, metadata, atSign validation,
  root-domain parsing, verb builders for the Atsign Protocol wire
  format, and the exception hierarchy.
- [at_contact](./packages/at_contact): contacts library that
  persists across different Atsign Platform applications.
- [at_lookup](./packages/at_lookup): low-level direct
  implementation of the Atsign Protocol verbs. Used by `at_client`
  and `at_client_flutter`.
- [at_onboarding_cli](./packages/at_onboarding_cli): the
  `at_register` and `at_activate` command-line tools for registering,
  activating and enrolling atSigns, and a small library for programs
  that drive the same flows headlessly.
- [at_policy](./packages/at_policy): scaffolding for building
  policy-management services that talk to enforcement endpoints
  via the Atsign Protocol.
- [at_server_status](./packages/at_server_status): logs the status
  of the root server and the atServer for an atSign of your
  choice.
- [at_utils](./packages/at_utils): utility library: atSign,
  metadata, configuration, logger.
- [base2e15](./packages/base2e15): fork of the upstream
  [base2e15](https://pub.dev/packages/base2e15) package, kept here
  for null-safety support.
- [dart_utf7](./packages/dart_utf7): fork of the upstream
  [utf7](https://pub.dev/packages/utf7) package, kept here for
  null-safety support.

## Flutter packages

[![Build Status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_widgets.yml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_widgets.yml)

> **Status:** Most of the `at_*_flutter` packages listed below are
> in the process of being deprecated. Over the next few months
> they'll be replaced by example application code rather than
> reusable widget packages. The recommended path for new Flutter
> work is to read the example app at
> [`packages/at_client_flutter/examples/todos`](./packages/at_client_flutter/examples/todos)
> and adapt it directly. The packages will continue to publish
> until that migration completes.

- [at_backupkey_flutter](./deprecated/flutter/at_backupkey_flutter):
  deprecated; export the keys with `FileAtKeysIo` as the
  [at_client_flutter README](./packages/at_client_flutter/README.md#exporting-atkeys)
  shows.
- [at_chat_flutter](./packages/at_chat_flutter): chat feature
  using atSigns and the Atsign Protocol.
- [at_common_flutter](./deprecated/flutter/at_common_flutter): common
  widgets used by other Atsign Flutter packages. **Already
  deprecated** in favour of `at_client_flutter`.
- [at_contacts_flutter](./packages/at_contacts_flutter):
  contact-management widgets for atSign-based apps.
- [at_contacts_group_flutter](./packages/at_contacts_group_flutter):
  group functionality on top of `at_contacts_flutter`.
- [at_events_flutter](./packages/at_events_flutter): event
  management.
- [at_follows_flutter](./packages/at_follows_flutter): a basic
  social "follows" feature for atSigns.
- [at_invitation_flutter](./deprecated/flutter/at_invitation_flutter):
  deprecated; invite contacts via SMS or email using the
  [`at_client_flutter` snippet](./packages/at_client_flutter/example/lib/snippets/at_invitation.dart).
- [at_location_flutter](./packages/at_location_flutter): share
  location between two atSigns and view on
  [OpenStreetMap](https://www.openstreetmap.org/).
- [at_login_flutter](./packages/at_login_flutter): zero-trust
  logins using the Atsign Protocol.
- [at_notify_flutter](./packages/at_notify_flutter): notification
  surface.
- [at_sync_ui_flutter](./packages/at_sync_ui_flutter): UI
  indicator for the SDK's sync process.
- [at_theme_flutter](./packages/at_theme_flutter): theme
  switching.

## Post-quantum cryptography

The SDK can protect everything an adversary could record today — data
shared between atSigns, an atSign's own data, and the secrets an
enrollment approval hands a new device — with post-quantum key
establishment, and can authenticate with a post-quantum signature. It is
opt-in per client, through one setting:

```dart
final preference = AtClientPreference(posture: PqPosture.pqReady)
  ..namespace = 'todos';
```

| Posture                      | Authentication                                                  | Data written                                     | Reads post-quantum data |
| ---------------------------- | --------------------------------------------------------------- | ------------------------------------------------ | ----------------------- |
| `PqPosture.legacy` (default) | RSA-2048                                                        | legacy encryption                                | no                      |
| `PqPosture.pqReady`          | ML-DSA-65; publishes a key package and this atSign's namespace keys | legacy encryption, so pre-quantum peers read it | yes                     |
| `PqPosture.pqActive`         | ML-DSA-65, and an ML-DSA-65 data signing key                    | post-quantum by default; legacy writes refused   | yes                     |

Under the hood, each namespace an atSign owns gets a key-establishment
keypair — the X-Wing hybrid (ML-KEM-768 + X25519) by default, pure
ML-KEM-1024 on request — published as a signed advertisement; a writer
establishes a content key to the recipient's namespace key and encrypts
the record with AES-256-GCM, and a sender follows whatever the recipient
advertised. An enrollment submitted under a post-quantum posture
advertises a key package, and the approving client seals the atSign's
secrets to it rather than wrapping them with RSA. A client whose posture
asks for a stronger authentication key than its enrollment holds
re-enrolls itself at its first start, filing the new enrollment in the
same keys store beside the legacy fields. ML-DSA authentication needs an
atServer that verifies it; a `legacy` client makes no such demand.

The developer's view is in the
[at_client README](./packages/at_client/README.md#post-quantum-cryptography);
the design is under [`docs/projects/pq/`](./docs/projects/pq/roadmap.md).

## Upgrading

Applications talk to `at_client` (3.x, a minor release), so most need no
code change: the new lifecycle verbs sit beside `AtClientManager`, whose
`setCurrentAtSign` is deprecated rather than removed. The packages that
take a major are the ones that used to hand at_auth's types to an app:

- **at_client_flutter 1.x → 2.0**: `AuthService` and
  `FlutterEnrollmentService` are gone; the dialogs take the atSign, the
  keys store and the preference, and hand back the `AtClient`. Nothing
  from at_auth is re-exported. The table is in the
  [at_client_flutter README](./packages/at_client_flutter/README.md#migrating-from-1x).
- **at_onboarding_cli 1.x → 2.0**: `at_activate` names its command
  (`at_activate onboard -a @alice`), `--posture` replaces
  `--signingAlgoType`, and `AtOnboardingService` keeps `authenticate()`
  and `atClient` while `onboard`, `enroll` and `close` become
  `Atsign.activate`, `Atsign.enroll` and `atClient.stop()`. The table is in
  the [at_onboarding_cli README](./packages/at_onboarding_cli/README.md#migrating-from-1x).
- **at_auth 3.x → 4.0**: `AtAuth` and its request and response objects
  are gone; activation is `activateAtSign(...)`, logging in and every
  enrollment decision are at_client's. The table is in the
  [at_auth README](./packages/at_auth/README.md#migrating-from-3x).

If you happen to import `at_onboarding_cli` or `at_auth` directly — which
almost no application does — the short version is: replace the call that
built your client with `Atsign('@alice').open(keys: ..., preference: ...)`,
`.activate(...)` or `.enroll(...)`, drop the import, and read everything
else off the `AtClient` you get back.

## Installation

Each package's own README and pub.dev page have the installation
details. Click any of the links above.

## AI Agent Skill

The `at_client_skills` package gives AI agents accurate, up-to-date knowledge of
`at_client` and `at_client_flutter` — covering `AtCollection<T>`, auth flows,
querying, sub-collections, testing patterns, and common pitfalls.

```sh
# Add to your project
dart pub add --dev at_client_skills skills

# Install the skill into your IDE
dart run skills get
```

Works with Claude Code, Cursor, GitHub Copilot, Cline, and any agent
supporting the [agentskills.io](https://agentskills.io) specification.

## Maintainers

[Atsign Foundation core devs](https://github.com/orgs/atsign-foundation/teams/atcoredevs)
