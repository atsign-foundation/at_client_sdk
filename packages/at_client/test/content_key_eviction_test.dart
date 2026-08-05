import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    show CommitOp;
import 'package:test/test.dart';

/// The eviction trigger for coarse forward secrecy: a client drops a cached
/// content key when it observes that key's conveyance record being deleted.
///
/// Deleting the record stops anyone unwrapping the CK *again*. It says nothing
/// about the clients that already did — they hold the plaintext and would go on
/// reading the very data the deletion was meant to close off. Sync carries the
/// deletion to them; this turns arrival into eviction.
void main() {
  const atSign = '@alice';
  const namespace = 'app_1.my_apps';

  ContentKey ck(int seed) =>
      ContentKey(Uint8List.fromList(List<int>.generate(32, (i) => seed + i)));

  SyncProgress synced(List<KeyInfo> keys) => SyncProgress()
    ..atSign = atSign
    ..syncStatus = SyncStatus.success
    ..keyInfoList = keys;

  group('the key string a conveyance record arrives as', () {
    test('splits a self conveyance into its CK and namespace', () {
      expect(ContentKeyEviction.parse('abc123.__ck.$namespace$atSign'),
          (ckKid: 'abc123', ckNs: namespace),
          reason: 'a multi-segment namespace is why this is parsed on the '
              '.__ck. marker rather than by AtKey.fromString, which cuts at '
              'the LAST dot and would report the namespace as "my_apps"');
    });

    test('splits an inbound conveyance, which names its recipient first', () {
      expect(ContentKeyEviction.parse('@alice:abc123.__ck.$namespace@bob'),
          (ckKid: 'abc123', ckNs: namespace));
    });

    test('declines anything that is not a conveyance record', () {
      for (final key in [
        '@alice:treaty.$namespace@bob',
        'public:__nskey.$namespace$atSign',
        '__ckcur.alice.$namespace$atSign',
        'abc123.__ck.$namespace',
        '.__ck.$namespace$atSign',
        'abc123.__ck.$atSign',
      ]) {
        expect(ContentKeyEviction.parse(key), isNull, reason: key);
      }
    });
  });

  group('eviction', () {
    late ContentKeyCache cache;
    late ContentKeyEviction eviction;
    late ContentKey key;

    setUp(() {
      cache = ContentKeyCache();
      eviction = ContentKeyEviction(cache, atSign);
      key = ck(1);
      cache.putAsCurrent(atSign, namespace, key, 'gen1');
    });

    test('an observed deletion drops the key', () {
      eviction.onSyncProgressEvent(synced([
        KeyInfo('${key.ckKid}.__ck.$namespace$atSign',
            SyncDirection.remoteToLocal, CommitOp.DELETE)
      ]));

      expect(cache.get(atSign, namespace, key.ckKid), isNull);
      expect(cache.current(atSign, namespace), isNull,
          reason: 'the key it was current under is gone, so there is no '
              'current CK either — the next write cuts a fresh one');
    });

    test('an update of the same record does not', () {
      eviction.onSyncProgressEvent(synced([
        KeyInfo('${key.ckKid}.__ck.$namespace$atSign',
            SyncDirection.remoteToLocal, CommitOp.UPDATE)
      ]));

      expect(cache.get(atSign, namespace, key.ckKid), isNotNull,
          reason: 'a conveyance arriving is the ordinary case — evicting on '
              'it would throw away a key the moment it was delivered');
    });

    test('a local write pushed to the server does not', () {
      eviction.onSyncProgressEvent(synced([
        KeyInfo('${key.ckKid}.__ck.$namespace$atSign',
            SyncDirection.localToRemote, CommitOp.DELETE)
      ]));

      expect(cache.get(atSign, namespace, key.ckKid), isNotNull,
          reason: 'this client already evicted through CkManager when it made '
              'the delete; reacting to its own push back would mean being '
              'right about a case this never sees');
    });

    test('a deletion in another namespace leaves this one alone', () {
      eviction.onSyncProgressEvent(synced([
        KeyInfo('${key.ckKid}.__ck.app_2.my_apps$atSign',
            SyncDirection.remoteToLocal, CommitOp.DELETE)
      ]));

      expect(cache.get(atSign, namespace, key.ckKid), isNotNull,
          reason: 'ckKids are unique within a namespace, not across them — '
              'the same identity discipline the cache is keyed by');
    });

    test('a batch evicts every conveyance it carries and ignores the rest', () {
      final second = ck(100);
      cache.put(atSign, namespace, second);

      eviction.onSyncProgressEvent(synced([
        KeyInfo('treaty.$namespace$atSign', SyncDirection.remoteToLocal,
            CommitOp.DELETE),
        KeyInfo('${key.ckKid}.__ck.$namespace$atSign',
            SyncDirection.remoteToLocal, CommitOp.DELETE),
        KeyInfo('${second.ckKid}.__ck.$namespace$atSign',
            SyncDirection.remoteToLocal, CommitOp.DELETE),
      ]));

      expect(cache.get(atSign, namespace, key.ckKid), isNull);
      expect(cache.get(atSign, namespace, second.ckKid), isNull);
    });

    test('a progress event carrying no keys is harmless', () {
      eviction.onSyncProgressEvent(SyncProgress()..atSign = atSign);

      expect(cache.get(atSign, namespace, key.ckKid), isNotNull);
    });
  });

  group('wiring', () {
    // The listener is only a mechanism if a client registers it. Nothing else
    // in the SDK reacts to a deleted conveyance, so an unregistered listener
    // would leave every client reading data the deletion was meant to close
    // off, with the unit tests above all green.
    tearDown(() async {
      for (final client
          in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
        await (client as AtClientImpl).stop();
      }
      AtClientImpl.atClientInstanceMap.clear();
    });

    test('a client registers the eviction listener on its sync service',
        () async {
      final client = await AtClientImpl.create(
          '@evictionwiring',
          'test',
          AtClientPreference()
            ..hiveStoragePath = 'test/hive/evictionwiring'
            ..commitLogPath = 'test/hive/evictionwiring') as AtClientImpl;
      final registered = <SyncProgressListener>[];
      final sync = _RecordingSyncService(registered);

      client.syncService = sync;

      expect(registered.whereType<ContentKeyEviction>(), hasLength(1));
      expect(registered.whereType<ContentKeyEviction>().single.cache,
          same(CryptoConfig.forClient(client).contentKeyCache),
          reason: 'and on the SAME cache the providers read — a listener '
              'evicting from a cache nobody reads is indistinguishable from '
              'no listener at all');
    });
  });
}

/// A [SyncService] that only records the listeners added to it.
class _RecordingSyncService implements SyncService {
  final List<SyncProgressListener> registered;

  _RecordingSyncService(this.registered);

  @override
  void addProgressListener(SyncProgressListener listener) =>
      registered.add(listener);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
