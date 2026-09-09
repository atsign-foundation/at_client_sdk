/// An install that stands in for a build predating the post-quantum schemes,
/// reading a record one of those schemes wrote.
///
/// `PqPosture.legacy` is the one posture whose `configuresPqProviders` is
/// false, and the era `CryptoConfig` it adopts registers no post-quantum
/// provider at all, so a record stamped with one of their ids has nothing to
/// resolve to: the read stops at provider routing and throws
/// `CryptoProviderNotRegistered` naming the id it could not find.
library;

import 'dart:convert';
import 'dart:io';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

void main() {
  const atSign = '@alice';
  const namespace = 'wavi';

  // NOTE: raw literals rather than the SDK constants that define them. Both
  // are at-rest values, so comparing them against their own constants would
  // pin nothing; an intended change edits these two lines.
  const pqProviderId = 'at/symmetric/AES/GCM';
  const legacyProviderId = 'legacy';

  const plaintext = 'written before any of this';

  final storageDir = '${Directory.current.path}/test/hive/legacy_refusal';

  /// What the atServer serves for a record — the stored value and the raw
  /// `metaData` object — keyed by the at-key string a lookup command carries.
  final records = <String, ({String value, Map<String, dynamic> metaData})>{};

  AtKey record(String name) => AtKey()
    ..key = name
    ..namespace = namespace
    ..sharedBy = atSign;

  Map<String, dynamic> wireMeta(String providerId) => {
        'isEncrypted': true,
        'appMetadata':
            Metadata.encodeAppMetadata(AppMetadata(providerId: providerId)),
      };

  GetRequestOptions fromTheAtServer() =>
      GetRequestOptions()..useRemoteAtServer = true;

  late AtClient legacyOnly;

  setUpAll(() async {
    registerFallbackValue(FakeLookupVerbBuilder());

    final remoteSecondary = MockRemoteSecondary();
    when(() => remoteSecondary.executeVerb(any(),
            sync: any(named: 'sync'),
            cameFromServer: any(named: 'cameFromServer')))
        .thenAnswer((invocation) async {
      final builder = invocation.positionalArguments[0];
      final command = builder.buildCommand() as String;
      final match = records.entries.firstWhere(
        (entry) => command.contains(entry.key),
        orElse: () =>
            MapEntry('', (value: '', metaData: const <String, dynamic>{})),
      );
      if (match.key.isEmpty) return 'data:null';
      return 'data:${jsonEncode({
            'key': match.key,
            'data': match.value.value,
            'metaData': match.value.metaData,
          })}';
    });

    final atChopsKeys = MockAtChopsKeys();
    when(() => atChopsKeys.selfEncryptionKey)
        .thenReturn(AESKey('REqkIcl9HPekt0T7+rZhkrBvpysaPOeC2QL1PVuWlus='));

    // NOTE: a real client, so the posture chooses the era `CryptoConfig` at
    // construction; handing one in directly would make both arms a statement
    // about the fixture.
    legacyOnly = await AtClientImpl.create(
      atSign,
      namespace,
      AtClientPreference(posture: PqPosture.legacy)
        ..hiveStoragePath = storageDir
        ..commitLogPath = '$storageDir/commit',
      remoteSecondary: remoteSecondary,
      atChops: AtChopsImpl(atChopsKeys),
    );

    records[record('pq_stamped').toString()] = (
      value: 'ciphertext this install never opens',
      metaData: wireMeta(pqProviderId)
    );

    // NOTE: the control's record is encrypted by this client's own write
    // path, so the control arm is a round trip rather than a fixture agreeing
    // with itself.
    final written = record('legacy_stamped');
    final ciphertext =
        await CryptoRuntime(legacyOnly).encryptForPut(written, plaintext);
    records[written.toString()] =
        (value: ciphertext, metaData: wireMeta(legacyProviderId));
  });

  tearDownAll(() async {
    try {
      await Hive.close();
      AtClientImpl.atClientInstanceMap.clear();
      if (Directory(storageDir).existsSync()) {
        Directory(storageDir).deleteSync(recursive: true);
      }
    } catch (_) {
      // NOTE: teardown must not mask a real failure in a test body.
    }
  });

  test('a legacy-only install refuses a record stamped at/symmetric/AES/GCM',
      () async {
    // NOTE: `CryptoConfig.forClient` falls back to the legacy config for a
    // client that was never given an era default at all, so the refusal below
    // has to be shown to come from an adopted era set rather than an absent
    // one.
    expect(CryptoConfig.eraDefaultFor(legacyOnly), isNotNull,
        reason: 'the posture must have adopted an era default, or the refusal '
            'below says nothing about what PqPosture.legacy configures');

    // NOTE: the message is asserted as well as the type — construction has
    // its own throw of the same type, so a bare type check would be green for
    // the wrong refusal.
    await expectLater(
        () => legacyOnly.get(record('pq_stamped'),
            getRequestOptions: fromTheAtServer()),
        throwsA(isA<CryptoProviderNotRegistered>()
            .having((e) => e.message, 'message', contains(pqProviderId))
            .having((e) => e.message, 'message',
                contains('Registered providers: $legacyProviderId.'))),
        reason: 'a client at this stage configures no post-quantum providers, '
            'so a record stamped with one must fail loudly at routing and say '
            'which scheme it is short of — not open, and not fail somewhere '
            'further on for an unrelated reason');
  });

  test('the control: the same install still reads a legacy-stamped record',
      () async {
    final read = await legacyOnly.get(record('legacy_stamped'),
        getRequestOptions: fromTheAtServer());

    expect(read.value, plaintext,
        reason: 'this install is a working reader of everything written under '
            'the scheme it does configure; if this is red the arm above '
            'measures a broken client rather than a withheld capability');
    expect(read.metadata?.appMetadata?.providerId, legacyProviderId,
        reason: 'and it routed on the record\'s own stamp, so the read really '
            'went through provider resolution');
  });
}
