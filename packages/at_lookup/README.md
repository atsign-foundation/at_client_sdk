<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_lookup)](https://pub.dev/packages/at_lookup) [![pub points](https://img.shields.io/pub/points/at_lookup?logo=dart)](https://pub.dev/packages/at_lookup/score) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_lookup library

## Overview:

The AtLookup Library is the low-level direct implementation of the Atsign Protocol verbs. The AtLookup package is an interface
to interact with the secondary server to execute commands(scan, update, lookup, llookup, plookup, etc).

## Get started:

### Installation:

To add this package as the dependency, add it to your pubspec.yaml

```dart  
dependencies:
  at_lookup: ^3.0.5
```

#### Add to your project

```sh
pub get 
```

#### Import in your application code

```dart
import 'package:at_lookup/at_lookup.dart';
```

### Clone it from github

Feel free to fork a copy of the source from the [GitHub Repo](https://github.com/atsign-foundation/at_libraries)

## Usage

### To get the instance of at_lookup

```dart
final AtLookupMuxable atLookUp = AtLookUp.withSecureSocket(
  atSign: '@alice',
  rootDomain: AtRootDomain.atsignDomain,
  transport: secureSocketTransport(SecureSocketConfig()),
  // How this connection authenticates, as one closure. at_lookup holds no key
  // material of its own; at_auth builds an authenticator from whatever
  // credential you have - a keystore, an AtChops, or a bare private key.
  // Pass null for a connection that never authenticates.
  authenticator: authenticatorFor(keysIo, '@alice'),
);
```

`withSecureSocket` returns an [`AtLookupMuxable`], which is an `AtLookUp` that
also carries the atServer's notification stream, so one connection and one
parser handle both of the atServer's framings.

### A factory, for a client that opens many connections

`AtLookUpFactory` is the function type an application hands at_client, so that
every connection a client opens travels the way the application chose;
`secureSocketLookUps` in `package:at_lookup/at_lookup_io.dart` is the default,
TLS on TCP:

```dart
import 'package:at_lookup/at_lookup_io.dart';

// TLS with your own settings.
final lookUps = secureSocketLookUps(
    config: SecureSocketConfig()..pathToCerts = '/certs');

// Behind a proxy that routes on the atSign: `onConnect` runs once on each new
// connection, before anything else is sent on it.
final viaProxy = secureSocketLookUps(
    onConnect: (connection) => connection.sendSync('from:@alice\n'));
```

A factory of your own returns any `AtLookupMuxable`. Each call names what the
connection is for: the atSign, the root domain, the authenticator (null for a
connection that never authenticates), an optional address finder and the
client config. The factory captures how bytes travel.
Please refer to [examples](https://github.com/atsign-foundation/at_libraries/blob/doc_at_lookup/at_lookup/example/bin/example.dart) for more details.

## Open source usage and contributions

This is freely licensed open source code, so feel free to use it as is, suggest changes or enhancements or create your
own version. See CONTRIBUTING.md for detailed guidance on how to setup tools, tests and make a pull request.