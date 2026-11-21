<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_lookup)](https://pub.dev/packages/at_lookup) [![pub points](https://img.shields.io/pub/points/at_lookup?logo=dart)](https://pub.dev/packages/at_lookup/score) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_lookup library

Upgrading from 3.x: see [Upgrading to at_client 4.0](https://github.com/atsign-foundation/at_client_sdk/blob/trunk/docs/upgrade-to-4.md).


## Overview:

The AtLookup Library is the low-level direct implementation of the Atsign Protocol verbs. The AtLookup package is an interface
to interact with an atServer: it sends verbs (scan, update, lookup, llookup, plookup and the rest) and reads their answers.

## Get started:

### Installation:

To add this package as the dependency, add it to your pubspec.yaml

```yaml
dependencies:
  at_lookup: ^4.0.0
```

#### Add to your project

```sh
dart pub get
```

#### Import in your application code

```dart
import 'package:at_lookup/at_lookup_io.dart';
```

`at_lookup.dart` is the transport-neutral half: the verbs, `AtLookUp`,
the outbound connection and the `AtTransport` interfaces. `at_lookup_io.dart` adds the
native TLS transport and the atDirectory lookup, and re-exports everything
above, so it is the one to import unless you are supplying your own transport
and address finder.

### Clone it from github

Feel free to fork a copy of the source from the [GitHub Repo](https://github.com/atsign-foundation/at_client_sdk)

## Usage

### To get the instance of at_lookup

```dart
import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_commons/at_commons.dart' show AtRootDomain;
import 'package:at_lookup/at_lookup_io.dart';

const root = AtRootDomain.atsignDomain;
final keysIo = FileAtKeysIo();   // the atSign's keyfile, from at_auth
final AtLookupMuxable atLookUp = AtLookUp.withSecureSocket(
  atSign: '@alice',
  rootDomain: root,
  transport: secureSocketTransport(SecureSocketConfig()),
  secondaryAddressFinder:
      CacheableSecondaryAddressFinder(root.rootDomain, root.rootPort),
  // How this connection authenticates, as one closure. at_lookup holds no key
  // material of its own; at_auth builds an authenticator from whatever
  // credential you have - a keystore, a bare private key, or a CRAM secret.
  // Pass null for a connection that never authenticates.
  authenticator: authenticatorFor(keysIo, '@alice'),
);
```

`withSecureSocket` returns an `AtLookupMuxable`, which is an `AtLookUp` that
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

// `onConnect` runs once on each new connection, before anything else is sent
// on it.
final withPreamble = secureSocketLookUps(
    onConnect: (connection) => connection.sendSync('noop:0\n'));
```

A root domain of `proxy:<host>` names a proxy fronting many atServers: every
atSign resolves to `<host>` at the root port, and the lookup sends
`from:<atSign>` first on each connection, before any `onConnect`, so that the
proxy knows which atServer the connection is for. Do not send it yourself.
The host may be a bracketed IPv6 literal, as in `proxy:[::1]`, over TLS.
Build such a root with `AtRootDomain('proxy:[::1]', port)`: at_commons'
`AtRootDomain.parse` refuses `proxy:[::1]:64` and `[::1]:64`, so a root read
from a command line or a settings dialog cannot name one yet.

A factory of your own returns any `AtLookupMuxable`. Each call names what the
connection is for: the atSign, the root domain, the authenticator (null for a
connection that never authenticates) and an optional address finder; the
client config goes to at_auth's `authenticatorFor(clientConfig:)`. The factory
captures how bytes travel.
Please refer to [examples](https://github.com/atsign-foundation/at_client_sdk/blob/trunk/packages/at_lookup/example/bin/example.dart) for more details.

## Open source usage and contributions

This is freely licensed open source code, so feel free to use it as is, suggest changes or enhancements or create your
own version. See CONTRIBUTING.md for detailed guidance on how to setup tools, tests and make a pull request.