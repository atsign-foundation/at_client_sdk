import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_client/sqlite.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:test/test.dart';

import 'storage_contract.dart' show FakeClient;

typedef _Store = AtKeyValueStore<String, AtData, AtMetaData?>;

/// The memory keystore answers as the SQLite keystore does: the same script of
/// writes run against both leaves every observable answer the same.
void main() {
  const atSign = '@parity';
  late AtClientStorage memory;
  late AtClientStorage sqlite;

  setUp(() async {
    memory = InMemoryAtClientStorage(atSign: atSign);
    sqlite = SqliteAtClientStorage(
        atSign: atSign, dbPath: SqliteAtClientStorage.inMemoryPath);
    await memory.attach(FakeClient(atSign, 'e1'));
    await sqlite.attach(FakeClient(atSign, 'e1'));
  });

  tearDown(() async {
    await memory.close();
    await sqlite.close();
  });

  final t0 = DateTime.utc(2026, 10, 28, 12);
  AtAssertedTimestamps at(int minutes, {DateTime? expires, DateTime? avail}) =>
      AtAssertedTimestamps(
          createdAt: t0.add(Duration(minutes: minutes)),
          updatedAt: t0.add(Duration(minutes: minutes)),
          expiresAt: expires,
          availableAt: avail);

  /// What a call answered, or the type of what it threw.
  Future<Object?> outcome(Future<Object?> Function() call) async {
    try {
      final v = await call();
      return switch (v) {
        Stream() => await v.toList(),
        AtData() => (v.data, _metadataJson(v.metaData)),
        AtMetaData() => _metadataJson(v),
        Map<String, AtData>() => {
            for (final MapEntry(:key, :value) in v.entries)
              key: (value.data, _metadataJson(value.metaData)),
          },
        _ => v,
      };
    } on Object catch (e) {
      return e.runtimeType;
    }
  }

  /// Runs [script] against both keystores, then asks both every question in
  /// [probes] and expects the same answers.
  Future<void> expectParity(Future<List<Object?>> Function(_Store s) script,
      Map<String, Future<Object?> Function(_Store s)> probes) async {
    final fromMemory = await script(memory.keyStore);
    final fromSqlite = await script(sqlite.keyStore);
    expect(fromMemory, fromSqlite, reason: 'what each write answered');
    for (final MapEntry(key: question, value: probe) in probes.entries) {
      expect(await outcome(() => probe(memory.keyStore)),
          await outcome(() => probe(sqlite.keyStore)),
          reason: question);
    }
  }

  const publicKey = 'public:name.wavi@parity';
  const sharedKey = '@bob:phone.wavi@parity';
  const selfKey = 'email.wavi@parity';
  const otherNs = 'public:name.buzz@parity';

  test('writes, rewrites and metadata answer the same', () async {
    await expectParity(
        (s) async => [
              await outcome(() => s.create(publicKey, AtData()..data = 'alice',
                  assertedTimestamps: at(0))),
              await outcome(() => s.put(
                  publicKey,
                  AtData()
                    ..data = 'alice-2'
                    ..metaData = (AtMetaData()..isBinary = true),
                  assertedTimestamps: at(1))),
              await outcome(() => s.put(
                  sharedKey,
                  AtData()
                    ..data = 'cipher'
                    ..metaData = (AtMetaData()
                      ..isEncrypted = true
                      ..sharedKeyEnc = 'ske'
                      ..pubKeyCS = 'cs'),
                  assertedTimestamps: at(2))),
              await outcome(() => s.putMeta(
                  selfKey, AtMetaData()..dataSignature = 'sig',
                  assertedTimestamps: at(3))),
              await outcome(() => s.putMeta(
                  sharedKey, AtMetaData()..ivNonce = 'iv',
                  assertedTimestamps: at(4))),
              await outcome(() => s.putAll(otherNs, AtData()..data = 'b',
                  AtMetaData()..encoding = 'base64')),
              await outcome(() => s.restore(
                  'public:restored.wavi@parity',
                  AtData()
                    ..data = 'kept'
                    ..metaData = (AtMetaData()
                      ..createdAt = t0
                      ..updatedAt = t0
                      ..immutable = true))),
              await outcome(
                  () => s.put(publicKey, AtData()..data = 'no-asserted-times')),
            ],
        {
          'the public key': (s) => s.get(publicKey),
          'the shared key': (s) => s.get(sharedKey),
          'a key written by metadata alone': (s) => s.get(selfKey),
          'its metadata': (s) => s.getMeta(selfKey),
          'a putAll key': (s) => s.get(otherNs),
          'a restored key': (s) => s.get('public:restored.wavi@parity'),
          'a missing key': (s) => s.get('public:nobody.wavi@parity'),
          'a missing key\'s metadata': (s) =>
              s.getMeta('public:nobody.wavi@parity'),
          'exists, any spelling': (s) => s.exists('PUBLIC:NAME.wavi@parity'),
          'every key': (s) => s.getKeys(),
          'keys matching a regex': (s) => s.getKeys(regex: r'\.wavi@'),
          'getMany': (s) => s.getMany([publicKey, sharedKey, 'nope@parity']),
          'a scan by namespace': (s) => s.scanKeys(
              const KeyPattern(namespace: 'wavi'),
              orderBy: OrderByKey.byKey),
          'a scan by sharedWith': (s) =>
              s.scanKeys(const KeyPattern(sharedWith: '@bob')),
          'a scan with skip and limit': (s) => s.scanKeys(
              const KeyPattern(sharedBy: '@parity'),
              orderBy: OrderByKey.byKey,
              skip: 1,
              limit: 2),
          'a scan by creation time': (s) =>
              s.scanKeys(const KeyPattern(), orderBy: OrderByKey.byCreatedAt),
          'the counts': (s) async {
            final stats = await s.stats();
            return [stats.totalKeys, stats.ttlKeys, stats.ttbKeys];
          },
        });
  });

  test('bad keys are refused the same way', () async {
    await expectParity(
        (s) async => [
              await outcome(() => s.put('not a key', AtData()..data = 'x')),
              await outcome(() => s.create(
                  'public:${'k' * 260}.wavi@parity', AtData()..data = 'x')),
              await outcome(() => s.getKeys(regex: '[')),
            ],
        {
          'nothing was written': (s) => s.getKeys(),
        });
  });

  test('expiry and availability answer the same', () async {
    final now = DateTime.now().toUtc();
    final past = now.subtract(const Duration(minutes: 1));
    final soon = now.add(const Duration(milliseconds: 300));
    final later = now.add(const Duration(hours: 1));
    await expectParity(
        (s) async => [
              await outcome(() => s.create(
                  'public:expired.wavi@parity', AtData()..data = 'x',
                  assertedTimestamps: at(0, expires: past))),
              await outcome(() => s.create(
                  'public:expiring.wavi@parity', AtData()..data = 'x',
                  assertedTimestamps: at(1, expires: later))),
              await outcome(() => s.create(
                  'public:hidden.wavi@parity', AtData()..data = 'x',
                  assertedTimestamps: at(2, avail: later))),
              await outcome(() => s.create(
                  'public:soon.wavi@parity', AtData()..data = 'x',
                  assertedTimestamps: at(3, avail: soon))),
              await outcome(() => s.create(
                  'public:plain.wavi@parity', AtData()..data = 'x',
                  assertedTimestamps: at(4))),
            ],
        {
          'what is visible now': (s) => s.getKeys(),
          'what has expired': (s) => s.getExpiredKeys(),
          'what expires first': (s) => s.nextExpiresAt(),
          'expired by a cutoff, limited': (s) => s.peekExpired(
              asOf: later.add(const Duration(minutes: 1)), limit: 1),
          'what becomes available next': (s) => s.nextAvailableAt(asOf: now),
          'what became available between two instants': (s) =>
              s.peekNewlyAvailable(since: now, asOf: later),
          'a scan that includes the expired': (s) => s.scanKeys(
              const KeyPattern(),
              includeExpired: true,
              orderBy: OrderByKey.byExpiresAt),
          'the counts': (s) async {
            final stats = await s.stats();
            return [stats.totalKeys, stats.ttlKeys, stats.ttbKeys];
          },
        });

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(await outcome(() => memory.keyStore.getKeys()),
        await outcome(() => sqlite.keyStore.getKeys()),
        reason: 'a key whose time-to-birth has passed is visible in both');
  });

  test('removal, bulk removal and expiry deletion answer the same', () async {
    final past = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    await expectParity(
        (s) async => [
              for (final k in [publicKey, sharedKey, selfKey, otherNs])
                await outcome(() =>
                    s.create(k, AtData()..data = k, assertedTimestamps: at(0))),
              await outcome(() => s.create(
                  'public:gone.wavi@parity', AtData()..data = 'x',
                  assertedTimestamps: at(1, expires: past))),
              await outcome(() => s.remove(publicKey)),
              await outcome(() => s.remove('public:never.wavi@parity')),
              await outcome(
                  () => s.removeMany([sharedKey, sharedKey, 'x@parity'])),
              await outcome(() => s.deleteExpiredKeys()),
            ],
        {
          'what is left': (s) => s.getKeys(),
          'what is left, expired included': (s) =>
              s.scanKeys(const KeyPattern(), includeExpired: true),
        });
  });

  test('a transaction applies its buffered writes the same way', () async {
    await expectParity((s) async {
      await s.create(publicKey, AtData()..data = 'before',
          assertedTimestamps: at(0));
      return [
        await s.transaction((txn) async {
          await txn.put(selfKey, AtData()..data = 'in-txn', null);
          await txn.remove(publicKey);
          return [
            (await txn.get(selfKey))?.data,
            await txn.exists(publicKey),
          ];
        }),
      ];
    }, {
      'what the transaction left': (s) => s.getKeys(),
      'the value it wrote': (s) async => (await s.get(selfKey))?.data,
    });
  });
}

/// [metaData] as the canonical JSON both keystores store, with the instants
/// a write stamps from the clock taken out: an asserted instant falls on a
/// whole minute of the test's day, and a stamped one almost never does.
Object? _metadataJson(AtMetaData? metaData) {
  if (metaData == null) return null;
  final json = {
    for (final MapEntry(:key, :value) in metaData.toJson().entries)
      if (value != null) key: value,
  };
  for (final field in ['createdAt', 'updatedAt']) {
    final at = json[field];
    if (at is String &&
        !(at.startsWith('2026-10-28 12:') && at.endsWith(':00.000Z'))) {
      json.remove(field);
    }
  }
  return jsonEncode(json);
}
