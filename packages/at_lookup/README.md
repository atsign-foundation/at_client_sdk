<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_lookup)](https://pub.dev/packages/at_lookup) [![pub points](https://img.shields.io/pub/points/at_lookup?logo=dart)](https://pub.dev/packages/at_lookup/score) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_lookup library

## Overview:

The AtLookup Library is the low-level direct implementation of the atProtocol verbs. The AtLookup package is an interface
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
AtLookUp atLookUp = AtLookupImpl(
  '@alice',
  'root.atsign.com',
  64,
  privateKey: 'privateKey',
  cramSecret: 'cramSecret',
);
```
Please refer to [examples](https://github.com/atsign-foundation/at_libraries/blob/doc_at_lookup/at_lookup/example/bin/example.dart) for more details.

## Open source usage and contributions

This is freely licensed open source code, so feel free to use it as is, suggest changes or enhancements or create your
own version. See CONTRIBUTING.md for detailed guidance on how to setup tools, tests and make a pull request.