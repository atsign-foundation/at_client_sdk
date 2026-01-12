import 'dart:io';

import 'package:args/args.dart';
import 'package:at_cli_commons/at_cli_commons.dart';

/// scan_example.dart
///
/// <br/>
/// Create an atClient and list the identifiers of all the records stored
/// in its atServer
Future<void> main(List<String> args) async {
  final ArgParser parser = CLIBase.createArgsParser(
      namespace: 'example', addLegacyRootDomainArg: true);
  try {
    var atClient =
        (await CLIBase.fromCommandLineArgs(args, parser: parser)).atClient;
    var allDataKeys = await atClient.getKeys(useRemoteAtServer: true);
    print(allDataKeys);
    exit(0);
  } catch (e, st) {
    print(e);
    if (e is ArgumentError || e is FormatException) {
      print(parser.usage);
    } else {
      print('Stack Trace:\n$st');
    }
    exit(1);
  }
}
