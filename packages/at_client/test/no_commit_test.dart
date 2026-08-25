/// Pins that the "do not record a commit" request reaches the wire.
///
/// The flag travels as `:nc` in the built command, and what the atServer sees
/// is whatever the *builder* copied into it — a round trip on the options
/// object would be green for a field nothing sends. So every assertion here is
/// over `buildCommand()`, as a raw literal, with and without the flag.
library;

import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/mint_lock.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show nskeyMintLockKey;
import 'package:at_client/src/transformer/request_transformer/put_request_transformer.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_utils/at_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

void main() {
  AtSignLogger.root_level = 'shout';

  setUpAll(() => registerFallbackValue(UpdateVerbBuilder()));

  AtKey selfKey() => AtKey()
    ..key = 'ordinary'
    ..namespace = 'testing'
    ..sharedBy = '@alice'
    ..metadata = (Metadata()..namespaceAware = true);

  Future<String> putCommandFor({required bool noCommit}) async {
    final builder = await PutRequestTransformer().transform(
        Tuple<AtKey, dynamic>()
          ..one = selfKey()
          ..two = 'a value',
        requestOptions: PutRequestOptions()
          ..shouldEncrypt = false
          ..noCommit = noCommit);
    return builder.buildCommand();
  }

  group('the put path carries the flag', () {
    test('a put that asks for no commit builds "update:nc:"', () async {
      // Pinned whole, and note where `:nc` sits — before the metadata
      // fragment, not after it.
      expect(await putCommandFor(noCommit: true),
          'update:nc:isEncrypted:false:ordinary.testing@alice a value\n');
    });

    test('and a put that does not ask is byte-identical but for that',
        () async {
      // The pair is the point: an assertion on the flagged form alone would
      // pass for a builder that emitted ":nc" unconditionally.
      expect(await putCommandFor(noCommit: false),
          'update:isEncrypted:false:ordinary.testing@alice a value\n');
    });

    test('the flag is off unless asked for', () {
      expect(PutRequestOptions().noCommit, isFalse);
      expect(DeleteRequestOptions().noCommit, isFalse);
    });
  });

  group('the delete path carries the flag', () {
    // Driven through the real `delete()` rather than by building a
    // DeleteVerbBuilder here: the builder already had the field, so asserting
    // on one built in the test would be green whether or not at_client passes
    // the option along.
    // A distinct atSign per call, deliberately: AtClientImpl.create caches one
    // client per atSign, so reusing @alice hands the second call the FIRST
    // client — still holding the first mock — and its recorder stays empty.
    Future<String> deleteCommandFor(
        {required bool noCommit, required String atSign}) async {
      final commands = <String>[];
      final remote = MockRemoteSecondary();
      when(() => remote.executeVerb(any(), sync: any(named: 'sync')))
          .thenAnswer((inv) async {
        commands.add(
            (inv.positionalArguments[0] as DeleteVerbBuilder).buildCommand());
        return 'data:-1';
      });
      final atClient = await AtClientImpl.create(
          atSign,
          'testing',
          AtClientPreference()
            ..hiveStoragePath = 'test/hive/no_commit'
            ..commitLogPath = 'test/hive/no_commit/commit'
            ..isLocalStoreRequired = false,
          remoteSecondary: remote);
      await atClient.delete(
          AtKey()
            ..key = 'ordinary'
            ..namespace = 'testing'
            ..sharedBy = atSign
            ..metadata = (Metadata()..namespaceAware = true),
          deleteRequestOptions: DeleteRequestOptions()
            ..useRemoteAtServer = true
            ..noCommit = noCommit);
      expect(commands, hasLength(1));
      return commands.single;
    }

    test('a delete that asks for no commit builds "delete:nc:"', () async {
      expect(await deleteCommandFor(noCommit: true, atSign: '@ncyes'),
          'delete:nc:ordinary.testing@ncyes\n');
    });

    test('and a delete that does not ask is identical but for that', () async {
      expect(await deleteCommandFor(noCommit: false, atSign: '@ncno'),
          'delete:ordinary.testing@ncno\n');
    });
  });

  group('the mint lock asks for no commit', () {
    test('taking a lock writes a command carrying ":nc"', () async {
      // The record the whole feature exists for: an interlock held for a few
      // seconds and abandoned to its ttl, whose commit entry every other
      // device would otherwise sync, expire and reclaim.
      final commands = <String>[];
      final atClient = MockAtClient();
      final remote = MockRemoteSecondary();
      when(() => atClient.getRemoteSecondary()).thenReturn(remote);
      when(() => atClient.enrollmentId).thenReturn('e-1');
      when(() => remote.executeVerb(any(), sync: any(named: 'sync')))
          .thenAnswer((inv) async {
        commands.add(
            (inv.positionalArguments[0] as UpdateVerbBuilder).buildCommand());
        return 'data:-1';
      });

      final lockKey = nskeyMintLockKey('@alice', 'testing',
          ttl: const Duration(seconds: 5));
      final held = await MintLock(atClient)
          .withLock<String>(lockKey, (lease) async => 'minted');

      expect(held, 'minted', reason: 'the lock was taken, so mint ran');
      expect(commands, hasLength(1));
      expect(commands.single, startsWith('update:nc:'),
          reason: 'a lock record must not cost a commit entry on every '
              'device that syncs this atSign');
    });
  });
}
