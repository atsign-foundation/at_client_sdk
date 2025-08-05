## Summary

A library of generic / reusable stuff which is useful when building cli programs
which use the [AtClient SDK](https://pub.dev/packages/at_client)

The simplest usage would be
```dart
  AtClient atClient = (await CLIBase.fromCommandLineArgs(args)).atClient;
```
For further usage examples, see 
- In the example/bin/ directory
  - `scan_example.dart`
  - `put_and_get_example.dart`
- The demo software [here](https://github.com/atsign-foundation/at_lorawan)

## Features

- The CLIBase class in cli_base.dart takes care of all the boilerplate
  involved in getting from program startup to having an AtClient object you can
  use - parsing command-line arguments, standard configuration, loading
  authentication keys, etc.
- There are a few other small utilities in utils.dart which CLIBase uses

## Open source usage and contributions

This is freely licensed open source code, so feel free to use it as is, suggest
changes or enhancements or create your own version.
See [CONTRIBUTING.md](../../CONTRIBUTING.md) for
detailed guidance on how to set up tools, tests and make a pull request.