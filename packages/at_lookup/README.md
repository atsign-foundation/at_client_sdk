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
  at_lookup: ^4.0.0
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
AtLookUp atLookUp = AtLookUp.legacy(
  '@alice',
  'root.atsign.com',
  64,
  pkamPrivateKey: pkamPrivateKey, // PKCS#8 DER bytes
);

await atLookUp.pkamAuthenticate();
```

at_lookup owns the wire protocol and makes no cryptographic choice of its own.
Two factories cover every consumer:

| Factory           | PKAM signing       | CRAM digest | Data signature verification |
| ----------------- | ------------------ | ----------- | --------------------------- |
| `AtLookUp.legacy` | RSA-2048 / SHA-256 | SHA-512     | RSA-2048 / SHA-256          |
| `AtLookUp.pq`     | ML-DSA-65          | SHA-512     | RSA-2048 / SHA-256          |

`AtLookUp.create` takes each algorithm individually — `signingAlgo`,
`hashingAlgo`, `dataAlgo`, all stateless at_chops algorithms — for a custom mix.
The `pkam` verb is stamped with what `signingAlgo` declares, so it cannot claim
one algorithm while another produced the signature.

`pkamPrivateKey` is the only key material at_lookup retains, and it is what keeps
a long-lived instance usable: when the atServer or an idle timeout drops the
connection, the next verb rebuilds it and re-authenticates without the caller
noticing. Omit it for an instance that only `cramAuthenticate`s, which is where
activation starts.

See [example/bin/example.dart](example/bin/example.dart) for a walkthrough of the
verbs.

## Open source usage and contributions

This is freely licensed open source code, so feel free to use it as is, suggest changes or enhancements or create your
own version. See CONTRIBUTING.md for detailed guidance on how to setup tools, tests and make a pull request.