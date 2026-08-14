import 'dart:io' show exit, stderr;

import 'package:at_client/at_client.dart' show AtClientPreference;
import 'package:at_utils/at_logger.dart' show AtSignLogger;

import 'connect.dart';
import 'exchange.dart';
import 'protocol.dart';

/// Which half of a cell this process is.
enum Role { sender, receiver }

/// How an arm turns a stage name and a spec into a preference.
///
/// The second version-specific step, and the reason the pair is
/// stage-parameterised at all: the current arm reads a `SigningRollout` off
/// the stage name, and the published arm cannot, because 3.14.0 has no such
/// type. Both are `AtClientPreference` by the time shared code sees them.
typedef PreferenceFor = AtClientPreference Function(
    ClientSpec spec, String stage);

/// Runs one half of one matrix cell and exits.
///
/// [stages] is what this build can honestly serve. A build asked for a stage
/// outside it fails loudly rather than falling back: the driver spawning the
/// wrong executable for a cell is precisely the bug that would make the
/// published column agree with `now` for the wrong reason.
Future<void> runArm(
  List<String> args, {
  required Role role,
  required Set<String> stages,
  required PreferenceFor preferenceFor,
  Attach attach = attachWithoutKeySource,
}) async {
  // at_client logs to stdout. The protocol carries its own sentinel so a log
  // line cannot be parsed as one, but a quiet run is easier to read when a
  // cell fails, and stderr keeps whatever does get logged out of the way.
  AtSignLogger.root_level = 'severe';

  try {
    final opts = _parse(args);
    final stage = opts['stage']!;
    if (!stages.contains(stage)) {
      throw ArgumentError.value(
          stage,
          'stage',
          'this build serves ${stages.join('|')} — a cell asking it for '
              'another stage is running the wrong executable');
    }

    final spec = ClientSpec(
      atSign: opts['atsign']!,
      namespace: opts['namespace'] ?? 'wavi',
      rootDomain: opts['root-domain'] ?? 'vip.ve.atsign.zone',
      rootPort: int.parse(opts['root-port'] ?? '64'),
      storagePath: opts['storage']!,
    );
    final exchange = ExchangeSpec(
      runId: opts['run-id']!,
      namespace: spec.namespace,
      peerAtSign: opts['peer']!,
      putCount: int.parse(opts['puts'] ?? '3'),
    );

    final client = await connect(
      spec: spec,
      preference: preferenceFor(spec, stage),
      attach: attach,
    );

    switch (role) {
      case Role.sender:
        await runSender(client, exchange);
      case Role.receiver:
        await runReceiver(client, exchange);
    }
    // The client holds a live connection and a sync timer; nothing here waits
    // on them, and the driver has what it came for.
    exit(0);
  } on Object catch (e, st) {
    emitFailure(e, st, during: role.name);
    stderr.writeln('$e\n$st');
    exit(1);
  }
}

/// `--key value` and `--key=value`, and nothing else.
///
/// Hand-rolled rather than `package:args` to keep the shared package's
/// dependency set to what both at_clients already pull in — a resolution
/// failure in the published arm would be a harness problem indistinguishable
/// from a finding.
Map<String, String> _parse(List<String> args) {
  final parsed = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) {
      throw ArgumentError.value(arg, 'argument', 'expected --name');
    }
    final eq = arg.indexOf('=');
    if (eq > 0) {
      parsed[arg.substring(2, eq)] = arg.substring(eq + 1);
    } else {
      if (i + 1 >= args.length) {
        throw ArgumentError.value(arg, 'argument', 'has no value');
      }
      parsed[arg.substring(2)] = args[++i];
    }
  }
  for (final required in ['stage', 'atsign', 'peer', 'run-id', 'storage']) {
    if (parsed[required] == null) {
      throw ArgumentError('--$required is required');
    }
  }
  return parsed;
}
