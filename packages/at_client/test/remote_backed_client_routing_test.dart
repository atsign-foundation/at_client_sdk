/// The substrate fixture can tell a local-first read from a remote-first one.
///
/// One map backing both local storage and the atServer leaves routing
/// invisible in results, and a test that can only assert the call proves the
/// argument was passed, never that it *means* anything. These rows prove the
/// fixture distinguishes the two by results, so a wrong route fails without
/// anybody remembering to look for one.
library;

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/remote_backed_client.dart';

void main() {
  setUpAll(() => registerFallbackValue(AtKey()));

  AtKey key(String name) => AtKey()
    ..key = name
    ..sharedBy = '@alice';

  group('with localData supplied, the two stores diverge', () {
    late Map<String, String> local;
    late Map<String, String> remote;
    late AtClient client;

    setUp(() {
      local = <String, String>{};
      remote = <String, String>{};
      client = buildRemoteBackedMockClient(
        atSign: '@alice',
        enrollmentId: 'e1',
        remoteData: remote,
        localData: local,
      );
    });

    test('a peer write is invisible to a local-first read and visible remotely',
        () async {
      // What a sibling enrollment published: it is on the atServer, and this
      // client has not synced.
      remote[key('__nskey.buzz').toString()] = 'siblings-key';

      // NOTE: closure form, not `expectLater(client.get(...), …)` — the
      // fixture throws synchronously, so the call never returns a Future to
      // await and the exception escapes the argument expression.
      expect(
        () => client.get(key('__nskey.buzz')),
        throwsA(isA<AtKeyNotFoundException>()),
        reason: 'a local-first read must miss a value only the atServer holds. '
            'If this passes, the fixture is answering local reads out of the '
            'remote store and cannot see the defect it exists to catch',
      );

      final remoteRead = await client.get(key('__nskey.buzz'),
          getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
      expect(remoteRead.value, 'siblings-key',
          reason: 'and the remote-first read must find it — without this '
              'control the miss above could just be an empty fixture');
    });

    test('a local-first write does not reach the atServer until sync',
        () async {
      await client.put(key('draft'), 'written-offline');

      expect(local[key('draft').toString()], 'written-offline');
      expect(remote.containsKey(key('draft').toString()), isFalse,
          reason: 'a local-first put must not appear on the atServer, or '
              'offline-write behaviour is untestable here');

      syncToRemote(localData: local, remoteData: remote);
      expect(remote[key('draft').toString()], 'written-offline',
          reason: 'and sync is what carries it across');
    });

    test('a remote-first write is on the atServer immediately', () async {
      await client.put(key('announcement'), 'now',
          putRequestOptions: PutRequestOptions()..useRemoteAtServer = true);

      expect(remote[key('announcement').toString()], 'now');
      expect(local.containsKey(key('announcement').toString()), isFalse,
          reason: 'remote-first bypasses local storage — this is the routing '
              'the nskey mint lock depends on, since the atomicity is the '
              'atServer refusing a second immutable create');
    });
  });

  test('without localData the historical single-store behaviour is unchanged',
      () async {
    // Callers that supply no localData specify this: a local-first write is
    // immediately readable by a local-first read.
    final remote = <String, String>{};
    final client = buildRemoteBackedMockClient(
      atSign: '@alice',
      enrollmentId: 'e1',
      remoteData: remote,
    );

    await client.put(key('shared'), 'v');
    expect((await client.get(key('shared'))).value, 'v');
    expect(remote[key('shared').toString()], 'v');
  });
}
