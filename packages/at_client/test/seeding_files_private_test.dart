// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures.
// ignore_for_file: experimental_member_use

/// A namespace key minted by startup seeding must be DURABLY filed before its
/// advertisement is published.
///
/// The mint's own contract enforces durable-before-published — but only
/// through the `privateFiling` its ring is built with. The client's data-path
/// ring gets one; a seeding ring built without one silently skips the filing
/// and publishes anyway, leaving the private in process memory only. Every
/// peer then seals to the advertised key; the first restart discards the only
/// copy of what opens those records, and rotation replaces the key without
/// decrypting the past. Nothing fails at the time — the loss surfaces as
/// unreadable records on some later day.
library;

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show envelopePayloadOf;
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
      AtClientPreference()
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

    // The mint publishes the advertisement only after the private is durable,
    // so the publish event is the assertion point: whatever should have been
    // filed has been by now.
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!events.any((e) => e.startsWith('update:public:__nskey.buzz'))) {
      if (DateTime.now().isAfter(deadline)) {
        fail('seeding never published an advertisement. '
            'Events:\n${events.join('\n')}');
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }

    final advertised = jsonDecode(remoteData['public:__nskey.buzz$atSign']!);
    final nskeyKid =
        (envelopePayloadOf(advertised as Map) as Map)['nskeyKid'] as String;

    final material = (await inner.read(atSign)).getKey(
        NskeyPrivateFiling.keyIdFor('buzz', nskeyKid),
        CryptographicKeyType.privateDecapsulation);
    expect(material, isNotNull,
        reason: 'the advertisement for generation $nskeyKid is live on the '
            'atServer, so peers are already sealing to it — but the private '
            'exists only in this process\'s memory. The first restart '
            'discards the only copy, and rotation cannot decrypt the past.');
    expect(material!.bytes.bytes, isNotEmpty);
  });
}
