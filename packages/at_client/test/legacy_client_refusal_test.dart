/// An install that stands in for a build predating the post-quantum schemes,
/// reading a record one of those schemes wrote.
///
/// `PqPosture.legacy` is the one posture whose `configuresPqProviders` is
/// false, and the era `CryptoConfig` it adopts registers no post-quantum
/// provider at all. So a record stamped with one of their ids has nothing to
/// resolve to: the read stops at provider routing and throws
/// `CryptoProviderNotRegistered` naming the id it could not find. Withholding
/// the capability — rather than deferring a default — is what makes this stage
/// a stand-in for a client that never had those providers, and this file is
/// where that inability is exercised rather than inspected.
///
/// Both arms drive `AtClient.get`, the call an application makes, against a
/// remote secondary serving the two records. Nothing here reaches into the
/// package's implementation: everything used comes from `package:at_client`'s
/// public surface, so the arms run the read path a consumer runs rather than a
/// routing helper called directly. What the unit arms cannot reach is a record
/// an actual post-quantum peer sealed; the live equivalent is this same `get`
/// against an atServer holding one.
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

  // Raw literals rather than the SDK constants that define them. Both are
  // at-rest values — what a writer stamped into a record's `appMetadata`, and
  // what a reader routes on — so comparing them against their own constants
  // would pin nothing. An intended change edits these two lines, and that edit
  // is the review.
  const pqProviderId = 'at/symmetric/AES/GCM';
  const legacyProviderId = 'legacy';

  const plaintext = 'written before any of this';

  final storageDir = '${Directory.current.path}/test/hive/legacy_refusal';

  /// What the atServer serves for a record — the stored value and the raw
  /// `metaData` object — keyed by the at-key string a lookup command carries.
  /// Raw rather than a serialised `Metadata`, so the fixture pins the bytes.
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
      // A record that is absent answers what a real lookup of a missing one
      // answers; it must not read as an empty value.
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

    // A real client, so the era `CryptoConfig` is chosen by the posture at
    // construction rather than named here. Handing it a config directly would
    // make both arms a statement about the fixture.
    legacyOnly = await AtClientImpl.create(
      atSign,
      namespace,
      AtClientPreference(posture: PqPosture.legacy)
        ..hiveStoragePath = storageDir
        ..commitLogPath = '$storageDir/commit',
      remoteSecondary: remoteSecondary,
      atChops: AtChopsImpl(atChopsKeys),
    );

    // The record a post-quantum peer sealed. Its value is never opened, so
    // what it holds is immaterial — the read stops at routing.
    records[record('pq_stamped').toString()] = (
      value: 'ciphertext this install never opens',
      metaData: wireMeta(pqProviderId)
    );

    // The control's record, encrypted by THIS client's own write path, so the
    // control arm is a round trip rather than a fixture agreeing with itself.
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
      // Teardown must not mask a real failure in a test body.
    }
  });

  test('a legacy-only install refuses a record stamped at/symmetric/AES/GCM',
      () async {
    // The posture must have GIVEN this client the legacy era set, not merely
    // left it without one: `CryptoConfig.forClient` falls back to the legacy
    // config for a client that was never given an era default at all, so a
    // refusal arriving that way would be green for a build whose posture had
    // stopped deciding anything.
    expect(CryptoConfig.eraDefaultFor(legacyOnly), isNotNull,
        reason: 'the posture must have adopted an era default, or the refusal '
            'below says nothing about what PqPosture.legacy configures');

    // Break-it: give `CryptoConfig.legacy`'s empty provider list a
    // `SymmetricAesGcmProvider`. The id then resolves, the read no longer
    // stops at routing, and this arm goes red — while the control below stays
    // green, because a legacy-stamped record routes to the built-in provider
    // either way. Named, not applied.
    //
    // The message is asserted as well as the type because this is about WHICH
    // refusal: a client refusing for some unrelated reason satisfies a bare
    // type check, and construction has its own throw of the same type with a
    // different message. Naming the registered set is what says this install
    // holds only the legacy provider.
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
    // Essential, and able to stay green while the arm above goes red: without
    // it, a client that refused EVERY record would satisfy the refusal
    // assertion, and a withheld capability would be indistinguishable from a
    // broken client. Same client, same `get`, same response path — only the
    // provider id the record carries, and the ciphertext under it, differ.
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
