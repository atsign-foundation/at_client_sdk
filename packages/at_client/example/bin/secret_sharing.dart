import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';

import 'package:at_client_examples/init_example_context.dart';

/// Alice-to-alice secret sharing: two clients of the SAME atSign exchange
/// secrets pairwise, end-to-end encrypted per client.
///
/// Run the receiver first (e.g. on one device / terminal):
///
///     dart bin/secret_sharing.dart -a @alice -R receiver
///
/// then run the sender (another terminal, same atSign — a different
/// enrollment is fine as long as both are authorized for the
/// `examples.demos` namespace):
///
///     dart bin/secret_sharing.dart -a @alice -R sender
///
/// The sender registers its client key bundle, discovers the receiver's
/// bundle, and shares a demo secret; the receiver decrypts it, stores it in
/// its SecretStore, and prints it. Other clients of @alice that sync the
/// envelope see only ciphertext.
void main(List<String> args) async {
  stdout.writeln('Same-atSign secret sharing');

  final ap = CLIBase.createArgsParser(namespace: applicationNamespace)
    ..addOption(
      'role',
      abbr: 'R',
      mandatory: true,
      help: 'Role (sender / receiver)',
    );
  late final ExampleRole role;
  late final AtClient atClient;
  try {
    final ar = ap.parse(args);
    role = ExampleRole.values.byName(ar['role']!.toString().toLowerCase());
    atClient = (await CLIBase.fromCommandLineArgs(args, parser: ap)).atClient;
  } catch (e) {
    stderr.writeln(ap.usage);
    stderr.writeln('\n$e');
    exit(1);
  }

  final sharing = AtClientSecretSharing(atClient);
  stdout.writeln(
    'Registering this client (generates an X-Wing post-quantum keypair)…',
  );
  // Registering with namespaces publishes a namespace-scoped copy of the
  // bundle per namespace, so senders can discover "clients participating in
  // this namespace" without fetching everyone's bundle.
  final myKeyPackage = await sharing.registerClient(
    namespaces: [applicationNamespace],
  );
  stdout.writeln(
    'Registered as clientId ${myKeyPackage.clientId} '
    '(enrollment ${myKeyPackage.enrollmentId}, '
    'namespaces ${myKeyPackage.namespaces})',
  );

  switch (role) {
    case ExampleRole.sender:
      await sender(sharing);
      break;
    case ExampleRole.receiver:
      await receiver(sharing);
      break;
  }
  await sharing.deregisterClient();
  exit(0);
}

Future<void> sender(AtClientSecretSharing sharing) async {
  // The secret to share, tagged with the application namespace. Only
  // enrollments authorized for that namespace can even fetch the envelope;
  // only the addressed client can decrypt it.
  await sharing.secretStore.putSecret(
    Secret(
      namespace: applicationNamespace,
      name: 'demo-api-key',
      value: 'hunter2-${DateTime.now().millisecondsSinceEpoch}',
    ),
  );

  stdout.writeln(
    '-> Discovering clients of this atSign participating in '
    '$applicationNamespace…',
  );
  final others = await sharing.discoverClients(namespace: applicationNamespace);
  if (others.isEmpty) {
    stdout.writeln(
      'No other registered clients found. Start the receiver '
      'first, then re-run the sender.',
    );
    return;
  }
  for (final bundle in others) {
    stdout.writeln(
      '-> Sharing secrets with client ${bundle.clientId} '
      '(enrollment ${bundle.enrollmentId})',
    );
    final n = await sharing.shareAllSecretsWith(bundle);
    stdout.writeln('-> Shared $n secret(s)');
  }

  // Envelopes are ordinary self keys: they reach the atServer via sync, so
  // don't exit until sync has pushed them.
  stdout.writeln('-> Waiting for sync to push the envelope(s)…');
  sharing.atClient.syncService.sync();
  await sharing.atClient.syncService.waitUntilCaughtUp(
    timeout: Duration(minutes: 2),
  );
  stdout.writeln('-> Envelope(s) on the atServer');
}

Future<void> receiver(AtClientSecretSharing sharing) async {
  sharing.sweepInterval = Duration(seconds: 10);
  sharing.receivedSecrets.listen((received) {
    stdout.writeln(
      '<- Received secret from client ${received.fromClientId} '
      '(enrollment ${received.fromEnrollmentId}):',
    );
    stdout.writeln(
      '     ${received.secret.namespace} '
      ': ${received.secret.name} = ${received.secret.value}',
    );
  });
  await sharing.startListening();
  stdout.writeln(
    'Listening for secrets for 5 minutes; '
    'run the sender now (same atSign)…',
  );
  await Future.delayed(Duration(minutes: 5));
  sharing.stopListening();
}
