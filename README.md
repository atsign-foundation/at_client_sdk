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
  devices.
- [at_client_flutter](./packages/at_client_flutter): the Flutter
  layer on top of `at_client`, for mobile and desktop apps.
  Adds onboarding / authentication dialogs and device-keychain
  storage. Flutter web is not a supported target.

## Libraries

[![Build Status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_libraries.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_libraries.yaml)

Dart libraries for building Atsign Platform applications. All are
published on
[pub.dev](https://pub.dev/publishers/atsign.org/packages).

- [at_auth](./packages/at_auth): platform-neutral core of
  onboarding, authentication, and APKAM enrollment.
- [at_chops](./packages/at_chops): cryptographic and hashing
  operations (encryption, decryption, signing, hashing) used by the
  rest of the SDK.
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
  and `at_client_mobile`.
- [at_onboarding_cli](./packages/at_onboarding_cli): command-line
  tooling and library surface for registering, onboarding, and
  enrolling atSigns. Useful for headless / IoT applications.
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

- [at_backupkey_flutter](./packages/at_backupkey_flutter): saves
  the backup key file for an onboarded atSign.
- [at_chat_flutter](./packages/at_chat_flutter): chat feature
  using atSigns and the Atsign Protocol.
- [at_common_flutter](./packages/at_common_flutter): common
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
- at_location_flutter has been removed. See
  [location_sharing](./packages/at_client_flutter/examples/location_sharing)
  for the app-owned `AtCollection<LocationShare>` replacement example, and
  [deprecated/flutter/at_location_flutter](./deprecated/flutter/at_location_flutter)
  for the tombstone.
- [at_invitation_flutter](./deprecated/flutter/at_invitation_flutter):
  deprecated; invite contacts via SMS or email using the
  [`at_client_flutter` snippet](./packages/at_client_flutter/example/lib/snippets/at_invitation.dart).
- [at_login_flutter](./packages/at_login_flutter): zero-trust
  logins using the Atsign Protocol.
- [at_notify_flutter](./packages/at_notify_flutter): notification
  surface.
- [at_sync_ui_flutter](./packages/at_sync_ui_flutter): UI
  indicator for the SDK's sync process.
- [at_theme_flutter](./packages/at_theme_flutter): theme
  switching.

## Installation

Each package's own README and pub.dev page have the installation
details. Click any of the links above.

## Maintainers

[Atsign Foundation core devs](https://github.com/orgs/atsign-foundation/teams/atcoredevs)
