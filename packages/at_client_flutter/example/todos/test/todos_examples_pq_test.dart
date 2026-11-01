import 'dart:io';
import 'dart:isolate';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:flutter_test/flutter_test.dart';
import 'package:todos/onboarding.dart';
import 'package:todos/services/todos_service.dart';

// NOTE: the CLI example's own files, by path, so the test opens the todos
// collection exactly as collections_todos.dart does.
// ignore: avoid_relative_lib_imports
import '../../../../at_client/example/lib/domain_objects.dart' as cli;
// ignore: avoid_relative_lib_imports
import '../../../../at_client/example/lib/todos_tui/todos_collection.dart'
    as cli;

const String _alice = '@alice🛠';
const String _bob = '@bob🛠';

/// A client for [atSign] on its demo keys, at [preference], against the
/// virtual atServer at [root].
Future<AtClient> _open(
  String atSign,
  AtClientPreference preference,
  String root,
) async {
  final [host, port] = root.split(':');
  // ignore: invalid_use_of_visible_for_testing_member
  final keys = InMemoryAtKeysIo();
  await keys.write(
    atSign,
    AtKeys.legacy(
      apkamPublicKey: demo.pkamPublicKeyMap[atSign]!,
      apkamPrivateKey: demo.pkamPrivateKeyMap[atSign]!,
      encryptionPublicKey: demo.encryptionPublicKeyMap[atSign]!,
      encryptionPrivateKey: demo.encryptionPrivateKeyMap[atSign]!,
      selfEncryptionKey: demo.aesKeyMap[atSign]!,
      apkamSymmetricKey: demo.apkamSymmetricKeyMap[atSign]!,
    ),
  );
  return Atsign(atSign).open(
    keys: keys,
    preference: preference
      ..rootDomain = host
      ..rootPort = int.parse(port),
    storage: InMemoryAtClientStorage(atSign: atSign, closedByClient: true),
    lookUps: secureSocketLookUps(),
    secondaryAddressFinder: CacheableSecondaryAddressFinder(
      host,
      int.parse(port),
    ),
  );
}

/// The titles [collection] lists once one of them is [title].
Future<List<String>> _titlesOnceListed<T>(
  AtCollection<T> collection,
  String title,
  String Function(T) titleOf,
) async {
  final items = await collection
      .query()
      .watch()
      .firstWhere((items) => items.any((i) => titleOf(i.obj) == title))
      .timeout(const Duration(minutes: 2));
  return [for (final i in items) titleOf(i.obj)];
}

/// Returns once [peer] has published its todos namespace key, as the public
/// readiness check reports it, so a todo shared with [peer] can be sealed.
Future<void> _untilReady(AtClient client, String peer) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (!await CryptoRuntime(client).isReadyFor(peer, cli.todosNamespace)) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$peer published no ${cli.todosNamespace} key within 2 minutes');
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}

/// The CLI example's side, as its own program would run it: its own isolate,
/// so its collection registry is its own. It shares [fromCli] with bob once
/// bob is ready, and answers with the titles it lists once [fromApp] has
/// arrived.
Future<(PqPosture, List<String>)> _cliSide(
  String root,
  String fromCli,
  String fromApp,
) => Isolate.run(() async {
  final client = await _open(_alice, cli.todosPreference(), root);
  try {
    final todos = await cli.openTodos(client);
    await _untilReady(client, _bob);
    await todos.create(
      obj: cli.Todo(title: fromCli, description: '', dueDate: DateTime.now()),
      sharedWith: {Atsign(_bob)},
    );
    return (
      client.getPreferences()!.posture,
      await _titlesOnceListed(todos, fromApp, (t) => t.title),
    );
  } finally {
    await client.stop();
  }
});

/// The CLI todos example and this app share todos with each other at
/// pqActive, through a virtual atServer whose root TODOS_VE_ROOT names, such
/// as vip.ve.atsign.zone:26000. Skipped without it.
///
/// Catalogue: features/at_client_flutter/todos_examples_pq.feature
void main() {
  final root = Platform.environment['TODOS_VE_ROOT'];

  test(
    'A todo shared between the CLI example and the Flutter app at pqActive '
    'is read on the other side, both ways',
    () async {
      final run = DateTime.now().microsecondsSinceEpoch;
      final fromCli = 'from the CLI example $run';
      final fromApp = 'from the Flutter app $run';
      final cliSide = _cliSide(root!, fromCli, fromApp);

      final appClient = await _open(_bob, todosPreference(), root);
      addTearDown(appClient.stop);
      expect(appClient.getPreferences()!.posture, PqPosture.pqActive);
      final app = TodosService(appClient);
      await app.init();
      await _untilReady(appClient, _alice);
      await app.createTodo(
        title: fromApp,
        description: '',
        dueDate: DateTime.now(),
        sharedWith: {Atsign(_alice)},
      );

      expect(
        await _titlesOnceListed(app.collection, fromCli, (t) => t.title),
        contains(fromCli),
        reason: 'the app lists the todo the CLI example shared',
      );
      final (cliPosture, cliTitles) = await cliSide;
      expect(cliPosture, PqPosture.pqActive);
      expect(
        cliTitles,
        contains(fromApp),
        reason: 'the CLI example lists the todo the app shared',
      );
    },
    skip: root == null ? 'set TODOS_VE_ROOT to a virtual atServer root' : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
