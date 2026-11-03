import 'dart:async';
import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart';

const String applicationNamespace = 'examples.demos';
const Duration exampleDefaultExpiration = Duration(minutes: 1);

/// How long a sender waits for the other atSigns to publish their key for
/// [applicationNamespace].
const Duration peerKeyWait = Duration(minutes: 5);

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
    atClient =
        (await CLIBase.fromCommandLineArgs(
          args,
          parser: ap,
          preference: AtClientPreference(posture: PqPosture.pqActive),
        )).atClient;
    if (role == ExampleRole.sender) {
      await _untilPublished(atClient, otherAtSigns!);
    }

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

/// Returns once each of [atSigns] has published a key for
/// [applicationNamespace], which a share to it at `PqPosture.pqActive` needs.
/// An atSign publishes one the first time it runs an example, so a sender
/// started first waits for the receiver, for at most [peerKeyWait].
Future<void> _untilPublished(AtClient atClient, Set<Atsign> atSigns) async {
  final crypto = CryptoRuntime(atClient);
  final deadline = DateTime.now().add(peerKeyWait);
  for (final atSign in atSigns) {
    var told = false;
    while (!await crypto.isReadyFor(atSign.toString(), applicationNamespace)) {
      if (DateTime.now().isAfter(deadline)) {
        stderr.writeln(
          '$atSign published no $applicationNamespace key within '
          '${peerKeyWait.inMinutes} minutes. Run this example as the '
          'receiver for $atSign, then run the sender again.',
        );
        exit(1);
      }
      if (!told) {
        stdout.writeln(
          'Waiting for $atSign to publish its $applicationNamespace key: '
          'run this example as the receiver for $atSign.',
        );
        told = true;
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }
}
