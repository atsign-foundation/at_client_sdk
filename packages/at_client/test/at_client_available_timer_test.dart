// Coverage for the visibility-aware emit logic and the
// availability-cache contract added in the `_availableTimer`
// machinery work. Drives `LocalSecondary._update` via UpdateVerbBuilder
// against a real HiveKeystore and observes events through the
// `onEvent` sink (the same hook AtClientImpl wires to its
// dataEvents stream in production).
//
// Note on metadata round-tripping: the at_commons `Metadata.availableAt`
// is a derived display-only field — the persistence layer reads
// `metadata.ttb` (int milliseconds-from-now-to-birth) and computes
// `availableAt` inside `AtMetadataBuilder.setTTB`. Tests therefore set
// `ttb` (and `ttl`), not `availableAt`/`expiresAt` directly.

import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtClient extends Mock implements AtClient {}

void main() {
  final storageDir = '${Directory.current.path}/test/hive_avail';
  const atSignStr = '@avail_test';

  late LocalSecondary local;
  late List<DataEvent> events;
  late _MockAtClient atClient;

  setUp(() async {
    AtClientImpl.atClientInstanceMap.remove(atSignStr);
    final commitLogInstance = await AtCommitLogManagerImpl.getInstance()
        .getCommitLog(atSignStr, commitLogPath: storageDir);
    final persistenceManager = SecondaryPersistenceStoreFactory.getInstance()
        .getSecondaryPersistenceStore(atSignStr)!;
    await persistenceManager.getHivePersistenceManager()!.init(storageDir);
    persistenceManager.getSecondaryKeyStore()!.commitLog = commitLogInstance;

    atClient = _MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(atSignStr);
    when(() => atClient.atSign).thenReturn(atSignStr.toAtsign());
    when(() => atClient.enrollmentId).thenReturn(null);

    events = <DataEvent>[];
    local = LocalSecondary(
      atClient,
      onEvent: events.add,
    );
  });

  tearDown(() async {
    await SecondaryPersistenceStoreFactory.getInstance().close();
    await AtCommitLogManagerImpl.getInstance().close();
    final dir = Directory(storageDir);
    if (await dir.exists()) {
      dir.deleteSync(recursive: true);
    }
  });

  AtKey atKey(String id) => AtKey.fromString('$id.test_ns$atSignStr');

  /// `ttbMs` is milliseconds-from-now-to-birth (positive = future,
  /// negative = past). `ttlMs` is milliseconds-from-now-to-expiry.
  UpdateVerbBuilder put(
    String id,
    String value, {
    int? ttbMs,
    int? ttlMs,
  }) {
    final k = atKey(id);
    if (ttbMs != null) k.metadata.ttb = ttbMs;
    if (ttlMs != null) k.metadata.ttl = ttlMs;
    return UpdateVerbBuilder()
      ..atKey = k
      ..value = value;
  }

  UpdateVerbBuilder updateMetaOnly(
    String id, {
    int? ttbMs,
    int? ttlMs,
  }) {
    final k = atKey(id);
    if (ttbMs != null) k.metadata.ttb = ttbMs;
    if (ttlMs != null) k.metadata.ttl = ttlMs;
    return UpdateVerbBuilder()
      ..atKey = k
      ..operation = AtConstants.updateMeta;
  }

  Duration approximate(DateTime a, DateTime b) => a.difference(b).abs();

  group('write-path emit matrix', () {
    test('fresh write, no ttb → one DataUpdated', () async {
      await local.executeVerb(put('a1', 'v1'));
      expect(events, hasLength(1));
      expect(events.single, isA<DataUpdated>());
    });

    test('fresh write, ttb in the future → no event', () async {
      await local.executeVerb(put('a3', 'v3', ttbMs: 3600 * 1000));
      expect(events, isEmpty);
    });

    test('update visible → visible: one DataUpdated', () async {
      await local.executeVerb(put('a4', 'v4'));
      events.clear();
      await local.executeVerb(put('a4', 'v4b'));
      expect(events, hasLength(1));
      expect(events.single, isA<DataUpdated>());
    });

    test('update visible → not-yet: one DataDeleted', () async {
      await local.executeVerb(put('a5', 'v5'));
      events.clear();
      await local.executeVerb(put('a5', 'v5b', ttbMs: 3600 * 1000));
      expect(events, hasLength(1));
      expect(events.single, isA<DataDeleted>());
    });

    test('update not-yet → visible: one DataUpdated', () async {
      await local.executeVerb(put('a6', 'v6', ttbMs: 3600 * 1000));
      events.clear();
      await local.executeVerb(put('a6', 'v6b'));
      expect(events, hasLength(1));
      expect(events.single, isA<DataUpdated>());
    });

    test('update not-yet → not-yet: no event', () async {
      await local.executeVerb(put('a7', 'v7', ttbMs: 3600 * 1000));
      events.clear();
      await local.executeVerb(put('a7', 'v7b', ttbMs: 7200 * 1000));
      expect(events, isEmpty);
    });

    test('updateMeta flips visible → not-yet: one DataDeleted', () async {
      await local.executeVerb(put('a8', 'v8'));
      events.clear();
      await local.executeVerb(updateMetaOnly('a8', ttbMs: 3600 * 1000));
      expect(events, hasLength(1));
      expect(events.single, isA<DataDeleted>());
    });
  });

  group('cache state', () {
    test('nextAvailableAt returns earliest pending future availableAt',
        () async {
      final t0 = DateTime.timestamp();
      await local.executeVerb(put('b1', 'v', ttbMs: 7200 * 1000)); // +2h
      await local.executeVerb(put('b2', 'v', ttbMs: 3600 * 1000)); // +1h
      final next = local.nextAvailableAt();
      expect(next, isNotNull);
      // Should be ~+1h; tolerate a few seconds of clock skew between the
      // builder's now and the test's t0.
      expect(approximate(next!, t0.add(const Duration(hours: 1))).inSeconds,
          lessThan(5));
    });

    test('nextAvailableAt is null when no future ttb is pending', () async {
      await local.executeVerb(put('b3', 'v'));
      expect(local.nextAvailableAt(), isNull);
    });

    test('past ttb (negative) does not enter the cache', () async {
      // Negative ttb produces an availableAt in the past — visible
      // immediately, no future fire to schedule.
      await local.executeVerb(put('b4', 'v', ttbMs: -3600 * 1000));
      expect(local.nextAvailableAt(), isNull);
    });

    test('keysWithAvailableAtAtOrBefore yields keys at-or-before cutoff',
        () async {
      final t0 = DateTime.timestamp();
      await local.executeVerb(put('c1', 'v', ttbMs: 30 * 1000)); // +30s
      await local.executeVerb(put('c2', 'v', ttbMs: 5 * 60 * 1000)); // +5m
      await local.executeVerb(put('c3', 'v', ttbMs: 60 * 60 * 1000)); // +1h

      final cutoff = t0.add(const Duration(minutes: 10));
      final picked = local.keysWithAvailableAtAtOrBefore(cutoff).toSet();
      expect(picked, hasLength(2));
      expect(picked.any((k) => k.contains('c1')), isTrue);
      expect(picked.any((k) => k.contains('c2')), isTrue);
      expect(picked.any((k) => k.contains('c3')), isFalse);
    });

    test('dropAvailabilityCacheEntry removes a single key', () async {
      await local.executeVerb(put('d1', 'v', ttbMs: 3600 * 1000));
      await local.executeVerb(put('d2', 'v', ttbMs: 3600 * 1000));

      final keys = local
          .keysWithAvailableAtAtOrBefore(
              DateTime.timestamp().add(const Duration(days: 365)))
          .toList();
      expect(keys, hasLength(2));
      local.dropAvailabilityCacheEntry(keys.first);

      final remaining = local
          .keysWithAvailableAtAtOrBefore(
              DateTime.timestamp().add(const Duration(days: 365)))
          .toList();
      expect(remaining, hasLength(1));
      expect(remaining.single, isNot(equals(keys.first)));
    });

    test('_delete drops both cache entries', () async {
      await local
          .executeVerb(put('e1', 'v', ttbMs: 3600 * 1000, ttlMs: 7200 * 1000));
      expect(local.nextAvailableAt(), isNotNull);
      expect(local.nextExpiryAt(), isNotNull);

      await local.executeVerb(DeleteVerbBuilder()..atKey = atKey('e1'));
      expect(local.nextAvailableAt(), isNull);
      expect(local.nextExpiryAt(), isNull);
    });
  });

  group('keystore-cache reuse', () {
    test('fresh LocalSecondary sees existing keystore TTB entries', () async {
      // The HiveKeystore's TTL/TTB cache is rebuilt by HiveKeystore
      // itself on box open; a freshly-constructed LocalSecondary
      // sharing the same keystore sees pending entries without an
      // explicit pre-warm walk.
      await local.executeVerb(put('p1', 'v', ttbMs: 3600 * 1000));

      final fresh = LocalSecondary(atClient, onEvent: events.add);
      expect(fresh.nextAvailableAt(), isNotNull);
      expect(
        approximate(fresh.nextAvailableAt()!,
                DateTime.timestamp().add(const Duration(hours: 1)))
            .inSeconds,
        lessThan(5),
      );
    });
  });

  group('fired-availability suppression', () {
    test('dropAvailabilityCacheEntry suppresses re-fire from sweep', () async {
      await local.executeVerb(put('s1', 'v', ttbMs: 3600 * 1000));
      final keys = local
          .keysWithAvailableAtAtOrBefore(
              DateTime.timestamp().add(const Duration(days: 365)))
          .toList();
      expect(keys, hasLength(1));

      // Simulate the timer fire: emit + drop.
      local.dropAvailabilityCacheEntry(keys.single);

      // Subsequent sweeps must skip the same key.
      final after = local
          .keysWithAvailableAtAtOrBefore(
              DateTime.timestamp().add(const Duration(days: 365)))
          .toList();
      expect(after, isEmpty);
      // And nextAvailableAt skips it too.
      expect(local.nextAvailableAt(), isNull);
    });

    test('rewriting a fired key with a new future ttb re-enables firing',
        () async {
      await local.executeVerb(put('s2', 'v', ttbMs: 3600 * 1000));
      final keys = local
          .keysWithAvailableAtAtOrBefore(
              DateTime.timestamp().add(const Duration(days: 365)))
          .toList();
      local.dropAvailabilityCacheEntry(keys.single);
      // Force a non-trivial sleep so the rewrite produces a strictly-later
      // availableAt — we need the new time to differ from the recorded one.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      events.clear();
      await local.executeVerb(put('s2', 'v2', ttbMs: 7200 * 1000));
      // No event from the write itself (future→future re-write).
      expect(events, isEmpty);
      // But the sweep should now see s2 again.
      final next = local.nextAvailableAt();
      expect(next, isNotNull);
      expect(
        approximate(next!, DateTime.timestamp().add(const Duration(hours: 2)))
            .inSeconds,
        lessThan(5),
      );
    });
  });
}
