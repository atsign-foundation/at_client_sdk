// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures.
// ignore_for_file: experimental_member_use

/// Records the ORDER of `_fileConveyedKeysAndAnchor`'s startup steps.
///
/// The ordering is a safety property with no string equivalent:
///
/// - **hydrate before sweep** — the sweep consumes and DELETES the envelopes
///   it finds, including other enrollments' pull requests, and answers them
///   from an in-memory store a restart empties. Hydrated afterwards, that
///   sweep destroys every request waiting for this holder while holding
///   nothing to answer them with.
/// - **root filed before anchor** — anchoring signs with the root private, so
///   collection must have run first or the same start cannot anchor.
/// - **reconcile before offer** — a held private that corresponds to nothing
///   published must be retired, not offered: offering it spends other
///   enrollments' broadcasts on bytes their own check rejects, and holding it
///   blocks this enrollment's own pull forever.
///
/// The steps deliberately have no injection seams (extracting them is the
/// refactor's business), so order is recorded through their observable
/// effects — keyfile reads/writes and wire operations on a mocked
/// RemoteSecondary — which is exactly the level that must survive the
/// extraction unchanged. The filer is fire-and-forget with no completion
/// handle, so the test waits for the last step's wire marker.
///
/// One ordering is NOT yet recorded here: anchor-before-pending-link. The
/// pending-link step emits nothing unless a conveyed chain link is already
/// in the secret store, which takes a genuinely sealed envelope from a peer
/// fixture — hand-building the sealed form would re-describe the wire
/// construction this suite exists to protect. That arm must exist before the
/// bootstrap extraction lands; until then the anchor-before-sweep assertion
/// bounds the anchor's position from the other side.
library;

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/recording_remote.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// Logs every keyfile operation into [events], delegating to [inner].
/// The inherited `update` routes through these, so it is recorded too.
class _RecordingAtKeysIo extends WrittenAtKeysIo {
  final InMemoryAtKeysIo inner;
  final List<String> events;

  _RecordingAtKeysIo(this.inner, this.events);

  @override
  Future<AtKeys> read(String atsign) async {
    events.add('keys:read');
    return inner.read(atsign);
  }

  @override
  Future write(String atsign, AtKeys atKeys) async {
    events.add('keys:write');
    return inner.write(atsign, atKeys);
  }

  @override
  Future<void> flush(Atsign atsign, AtKeys atKeys) async {
    events.add('keys:write');
    return inner.flush(atsign, atKeys);
  }
}

/// Generation 1 of a root filed under the algorithm this build mints.
final rootSlot1 =
    '${PqSigningRoot.keyIdPrefixFor(PqSigningRoot.rootKeyAlgoToken)}1';

void main() {
  const atSign = '@alice';
  const storageDir = 'test/hive/startup_order';

  late List<String> events;
  late Map<String, String> remoteData;
  late Map<String, Metadata> remoteMeta;

  setUpAll(() {
    registerFallbackValue(_FakeVerbBuilder());
  });

  setUp(() {
    events = [];
    remoteData = {};
    remoteMeta = {};
    AtClientImpl.atClientInstanceMap.clear();
  });

  tearDown(() async {
    try {
      await Hive.close();
      AtClientImpl.atClientInstanceMap.clear();
      final dir = Directory(storageDir);
      if (await dir.exists()) dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Waits for [marker] to appear in [events], failing after [timeout] —
  /// the filer is unawaited and exposes no completion future.
  Future<void> untilEvent(String marker,
      {Duration timeout = const Duration(seconds: 15)}) async {
    final deadline = DateTime.now().add(timeout);
    while (!events.any((e) => e.startsWith(marker))) {
      if (DateTime.now().isAfter(deadline)) {
        fail('no "$marker" event within $timeout — the startup chain did not '
            'reach it. Events so far:\n${events.join('\n')}');
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  int firstIndex(String prefix) {
    final i = events.indexWhere((e) => e.startsWith(prefix));
    expect(i, isNot(-1),
        reason: 'expected a "$prefix" event. Events:\n${events.join('\n')}');
    return i;
  }

  Future<AtClient> startClient(_RecordingAtKeysIo keysIo) =>
      AtClientImpl.create(
        atSign,
        'buzz',
        AtClientPreference()
          ..hiveStoragePath = storageDir
          ..commitLogPath = '$storageDir/commit',
        remoteSecondary: buildRecordingRemote(
            events: events, remoteData: remoteData, remoteMeta: remoteMeta),
        // A full keypair set: the put pipeline signs public records with the
        // encryption private key, served from atChops when it holds one.
        atChops: AtChopsImpl(AtChopsKeys.create(
            AtChopsUtil.generateAtEncryptionKeyPair(),
            AtChopsUtil.generateAtPkamKeyPair())),
        atKeysIo: keysIo,
      );

  test(
      'the start hydrates before it sweeps, files before it anchors, and '
      'anchors before the privileged sweep', () async {
    // A keyfile holding the root private whose public half IS the published
    // root, so every step has work: hydrate offers it, collection runs its
    // sweep, and anchoring self-signs a root link.
    final inner = InMemoryAtKeysIo();
    await inner.write(atSign, AtKeys());
    final pair = await MlDsa65PureDartAlgo().generateKeyPair();
    await PqSigningRoot(MockAtClient(), keysIo: inner)
        .store(atSign, pair.secretKey);
    // The published record, in the fixture shape pq_signing_root_test pins.
    remoteData['public:pq_signing_root$atSign'] =
        jsonEncode(apskAdvertisement(keys: [
      ApskSigningKey.forPublicKey(
          alg: PqSigningRoot.rootKeyAlgo, pub: base64Encode(pair.publicKey))
    ]));

    final keysIo = _RecordingAtKeysIo(inner, events);
    await startClient(keysIo);
    await untilEvent('cmd:enroll:list');

    // Hydrate before sweep. The marker must be hydrate-SPECIFIC: collection
    // also reads the keyfile, so a bare keys-read-before-scan assert stays
    // green with the steps swapped. Reconciliation's read of the published
    // root runs inside hydrate and nothing earlier touches that record, so
    // the FIRST root-record get is hydrate's own.
    final hydrateReconcile = firstIndex('get:public:pq_signing_root');
    final sweepScan = events.indexWhere((e) =>
        e.startsWith('scan:') && e.contains('__ssenv') ||
        e.startsWith('cmd:scan') && e.contains('__ssenv'));
    expect(sweepScan, isNot(-1),
        reason: 'the collection sweep never scanned for envelopes. '
            'Events:\n${events.join('\n')}');
    expect(hydrateReconcile, lessThan(sweepScan),
        reason: 'the sweep consumes and deletes pull requests and answers '
            'them from a store hydrate primes — swept-then-hydrated destroys '
            'every waiting request while holding nothing to answer with');

    // Root filed before anchor: collection (the sweep) completes before the
    // anchor's root-link publish starts. register() also rewrites the _apsk
    // (its initial bare publish, inside collection) — the anchor is the
    // rewrite that carries apskRootLink, so match the tag, not the key.
    final anchorPublish = events.indexWhere((e) => e.endsWith(':rootlink'));
    expect(anchorPublish, isNot(-1),
        reason: 'no _apsk rewrite carried apskRootLink — the start never '
            'anchored. Events:\n${events.join('\n')}');
    expect(sweepScan, lessThan(anchorPublish),
        reason: 'anchoring signs with the root private that collection files '
            '— anchored-then-filed needs a second start to anchor at all');

    // Anchor before the privileged chain sweep.
    final sweepCommand = firstIndex('cmd:enroll:list');
    expect(anchorPublish, lessThan(sweepCommand),
        reason: 'the sweep signs links for OTHER enrollments; a sweeper that '
            'has not anchored itself adds a hop without reaching the root');
  });

  test(
      'reconciliation gates the offer: an orphaned private is retired, '
      'never offered or anchored', () async {
    // The differential arm: the held private corresponds to NOTHING published
    // (a lost create's residue). Reconcile must retire it — a keyfile write —
    // and neither the offer nor the anchor may run on it.
    final inner = InMemoryAtKeysIo();
    await inner.write(atSign, AtKeys());
    final held = await MlDsa65PureDartAlgo().generateKeyPair();
    final published = await MlDsa65PureDartAlgo().generateKeyPair();
    await PqSigningRoot(MockAtClient(), keysIo: inner)
        .store(atSign, held.secretKey);
    remoteData['public:pq_signing_root$atSign'] = jsonEncode({
      ...apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(
            alg: PqSigningRoot.rootKeyAlgo,
            pub: base64Encode(published.publicKey))
      ]),
    });

    final keysIo = _RecordingAtKeysIo(inner, events);
    final client = await startClient(keysIo);
    // Not untilEvent('cmd:enroll:list'): with the orphaned private retired,
    // the sweep has nothing to sign root links with and correctly never
    // fetches the roster — so the completion signal must not depend on
    // which way the last step went.
    await (client as AtClientImpl).pqBootstrap!.startupComplete;

    // Retired: the active private is gone from the keyfile...
    final keysAfter = await inner.read(atSign);
    final active = keysAfter
        .atSignKeysForKeyId(rootSlot1)
        .where((m) => m.status == KeyPartStatus.active);
    expect(active, isEmpty,
        reason: 'an orphaned root private must be retired, or it blocks its '
            'own repair forever and gets offered to enrollments whose '
            'correspondence check rejects it after their broadcast is spent');

    // ...and nothing anchored with it: no _apsk rewrite carries a root link.
    expect(events.where((e) => e.endsWith(':rootlink')), isEmpty,
        reason: 'a link signed by a retired private verifies against nothing');
  });
}
