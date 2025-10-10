<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![GitHub License](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/atsign-foundation/at_client_sdk/badge)](https://securityscorecards.dev/viewer/?uri=github.com/atsign-foundation/at_client_sdk&sort_by=check-score&sort_direction=desc)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/8098/badge)](https://www.bestpractices.dev/projects/8098)

# at_client_sdk

at_client_sdk is the main repository for storing libraries related to building
applications with the atPlatform. The repository is broken up into multiple
categories:

- SDKs
- libraries
- widgets (currently in
  [at_widgets](https://github.com/atsign-foundation/at_widgets), but will be
  moved here soon)

## SDKs

[![Build Status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml)

This repo contains two versions of the at_client_sdk that you can choose from
depending on what kind of device you are targeting for your application.

- [at_client](./packages/at_client) a non platform specific SDK that can be used
for writing things like command line applications and headless apps for Internet
of Things (IoT) devices.

- [at_client_mobile](./packages/at_client_mobile) an SDK specifically written
for iOS and Android apps with support for secure storage and keys backup on the
device with embedded storage and hardware trusted root keychain.

## Libraries

[![Build Status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_libraries.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_libraries.yaml)

This repository also contains various atPlatform libraries for developers building
their own atPlatform applications. (These libraries can also be found on
[pub.dev](https://pub.dev/publishers/atsign.org/packages))

These libraries were previously located at
[at_libraries](https://github.com/atsign-foundation/at_libraries)

- [at_commons](https://pub.dev/packages/at_commons) Commonly used components
in implementation of the atProtocol.

- [at_utils](https://pub.dev/packages/at_utils) This is the Utility library
for atProtocol projects. It contains utility classes for atSign, atMetadata,
configuration and logger.

- [at_contact](https://pub.dev/packages/at_contact): A contacts library that
persists across different @ Platform applications. You can see this dependency
in action by cloning the at_chat_flutter project from the
[at_widgets repository](https://github.com/atsign-foundation/at_widgets).

- [at_lookup](https://pub.dev/packages/at_lookup): A low-level library that
directly implements the atProtocol verbs. You can find this dependency in
several other packages such as at_client and at_client_mobile.

- [at_onboarding_cli](https://pub.dev/packages/at_onboarding_cli): A command
line library to authenticate and onboard atSigns intended for use in
headless applications such as Internet of Things (IoT) devices.

- [at_server_status](https://pub.dev/packages/at_server_status): A helpful
library that logs the status of the root server as well as a secondary
server of your choice.

- [at_cli_commons](https://pub.dev/packages/at_cli_commons): A library of
generic / reusable stuff which is useful when building cli programs which
use the [atClient SDK](#SDKs)

## Flutter Packages

[![Build Status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_widgets.yml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_widgets.yml)

This repository also contains various atPlatform widgets for developers building
their own Flutter applications. (These libraries can also be found on
[pub.dev](https://pub.dev/publishers/atsign.org/packages))

These libraries were previously located at
[at_widgets](https://github.com/atsign-foundation/at_widgets)


- [at_backupkey_flutter](https://pub.dev/packages/at_backupkey_flutter)- A
flutter plugin project for saving the backup key of any atSign that is being
onboarded with atProtocol apps. Backup key can be used to authenticate in any
atProtocol apps.

- [at_chat_flutter](https://pub.dev/packages/at_chat_flutter)- A flutter plugin
project to provide a chat feature using atSigns and atProtocol.

- [at_common_flutter](https://pub.dev/packages/at_common_flutter)- A flutter
package to provide common widgets used by other Atsign flutter packages.

- [at_contacts_flutter](https://pub.dev/packages/at_contacts_flutter)- A
flutter plugin project to provide ease of managing contacts for an atSign
using atProtocol.

- [at_contacts_group_flutter](https://pub.dev/packages/at_contacts_group_flutter)-
A flutter plugin to provide group functionality for atSign contacts.

- [at_events_flutter](https://pub.dev/packages/at_events_flutter)- A flutter
plugin project to manage events.

- [at_location_flutter](https://pub.dev/packages/at_location_flutter)- A flutter
plugin project to share location between two atSigns and track them on Open
Street Map ([OSM](https://www.openstreetmap.org/)).

- [at_onboarding_flutter](https://pub.dev/packages/at_onboarding_flutter)- A
flutter plugin project for onboarding any atSign in atProtocol apps with ease.
Provides QRscanner and upload key file options to authenticate.

- [atsign_authentication_helper](https://pub.dev/packages/atsign_authentication_helper)-
(DISCONTINUED) A flutter plugin project to provide authentication for Atsign
apps. It provides both a QR scanner and feature to upload files.

- [at_follows_flutter](https://pub.dev/packages/at_follows_flutter)-  A flutter
plugin project to integrate follows feature for atSigns.

## How do I install?

All installation guidelines are written in their respective directories
and pub.dev sites. Click on the links above for those details.

## Maintainers

[Atsign Foundation core devs](https://github.com/orgs/atsign-foundation/teams/atcoredevs)
