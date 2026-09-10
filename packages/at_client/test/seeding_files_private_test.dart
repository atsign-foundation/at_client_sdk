// The substrate this exercises is marked @experimental.
// ignore_for_file: experimental_member_use

/// A namespace key minted by startup seeding must be DURABLY filed before its
/// advertisement is published.
///
/// The mint enforces that only through the `privateFiling` its ring is built
/// with: a seeding ring built without one publishes anyway, leaving the
/// private in process memory alone while every peer seals to it, and nothing
/// fails until a restart discards the only copy.
library;

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
import 'package:at_commons/at_builders.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/recording_remote.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

void main() {
  const atSign = '@alice';
  const storageDir = 'test/hive/seeding_files';

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

  test('the seeded private is in the keyfile by the time peers can seal to it',
      () async {
    final inner = InMemoryAtKeysIo();
    await inner.write(atSign, AtKeys());

    await AtClientImpl.create(
      atSign,
      'buzz',
      // NOTE: the posture is named rather than defaulted — the default runs no
      // post-quantum startup at all, and that startup is what this exercises.
      AtClientPreference(posture: PqPosture.pqReady)
        ..hiveStoragePath = storageDir
        ..commitLogPath = '$storageDir/commit'
        ..seedNamespaceKeys = true,
      remoteSecondary: buildRecordingRemote(
          events: events, remoteData: remoteData, remoteMeta: remoteMeta),
      atChops: AtChopsImpl(AtChopsKeys.create(
          AtChopsUtil.generateAtEncryptionKeyPair(),
          AtChopsUtil.generateAtPkamKeyPair())),
      atKeysIo: inner,
    );

    // NOTE: the mint publishes only after the private is durable, so the
    // publish event is the assertion point.
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!events.any((e) => e.startsWith('update:public:__nskey.buzz'))) {
      if (DateTime.now().isAfter(deadline)) {
        fail('seeding never published an advertisement. '
            'Events:\n${events.join('\n')}');
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }

    final advertised = jsonDecode(remoteData['public:__nskey.buzz$atSign']!);
    final nskeyKid = NskeyAdvertisement.fromPayload(
            SignedEnvelope.fromJson(advertised as Map).payload)
        .nskeyKid;

    final material = (await inner.read(atSign)).getAtSignKey(
        NskeyPrivateFiling.keyIdFor('buzz', nskeyKid),
        CryptographicMaterialRole.privateDecapsulation);
    expect(material, isNotNull,
        reason: 'the advertisement for generation $nskeyKid is live on the '
            'atServer, so peers are already sealing to it — but the private '
            'exists only in this process\'s memory. The first restart '
            'discards the only copy, and rotation cannot decrypt the past.');
    expect(material!.bytes.bytes, isNotEmpty);
  });
}
