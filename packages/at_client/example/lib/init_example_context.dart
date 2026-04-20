import 'dart:async';
import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';

const String applicationNamespace = 'examples.demos';
const Duration exampleDefaultExpiration = Duration(minutes: 1);

enum ExampleRole { sender, receiver }

typedef ExampleContext =
    ({
      ExampleRole role,
      AtClient atClient,
      Set<Atsign>? otherAtSigns,
      StreamController<String> progressController,
    });

/// To help with running examples, parse the command line args and determine
/// - whether we are acting as [ExampleRole.sender] or [ExampleRole.receiver]
/// - what the "other" atSigns are, if specified
Future<ExampleContext> getExampleContext(List<String> args) async {
  stdout.writeln('');
  final ap =
      CLIBase.createArgsParser(namespace: applicationNamespace)
        ..addOption(
          'other-at-signs',
          abbr: 'O',
          help: 'A list of the other atSign(s), comma-separated',
          mandatory: false,
          defaultsTo: '',
        )
        ..addOption(
          'role',
          abbr: 'R',
          mandatory: true,
          help: 'Role (sender / receiver)',
        );

  try {
    final ar = ap.parse(args);
    Set<Atsign>? otherAtSigns;
    final otherArg = ar['other-at-signs']!.trim().toString();
    if (otherArg.isNotEmpty) {
      otherAtSigns =
          otherArg
              .split(',')
              .map((s) => s.trim().toLowerCase().toAtsign())
              .toSet();
    }
    final ExampleRole role = ExampleRole.values.byName(
      ar['role']!.toString().toLowerCase(),
    );
    if (role == ExampleRole.sender) {
      if (otherAtSigns == null) {
        throw ArgumentError('sender role requires at least one other atSign');
      }
    }
    final AtClient atClient;
    atClient = (await CLIBase.fromCommandLineArgs(args, parser: ap)).atClient;

    ExampleContext c = (
      role: role,
      atClient: atClient,
      otherAtSigns: otherAtSigns,
      progressController: StreamController<String>(),
    );
    return c;
  } catch (e, st) {
    stderr.writeln(st);
    stderr.writeln(ap.usage);
    stderr.writeln();
    stderr.writeln('$e');
    exit(1);
  }
}
