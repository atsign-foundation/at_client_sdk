/// A namespace key minted by startup seeding must be DURABLY filed before its
/// advertisement is published.
///
/// The mint enforces that only through the `privateFiling` its ring is built
/// with: a seeding ring built without one publishes anyway, leaving the
/// private in process memory alone while every peer seals to it, and nothing
/// fails until a restart discards the only copy.
///
/// The client is an enrollment whose roster entry carries its key package,
/// since only such a client mints at all.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client_io.dart';
import 'package:at_client/at_client_mixins.dart' show AtClientSecretSharing;
import 'package:at_client/src/service/enrollment_service_impl.dart'
    show EnrollmentServiceImpl;
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/hive.dart' show HiveInstances;
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/recording_remote.dart';
import 'test_utils/ml_dsa_keyfile.dart';
import 'test_utils/hive_store.dart';
import 'test_utils/transport.dart';

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
      for (final c
          in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
        await c.stop();
      }
      // NOTE: both registries; the keystore's boxes live on a per-path
      // instance that Hive.close() does not reach.
      await HiveInstances.closeAll();
      await Hive.close();
      AtClientImpl.atClientInstanceMap.clear();
      final dir = Directory(storageDir);
      if (await dir.exists()) dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Enrollment e1 of [atSign], over [inner], listed for every namespace with
  /// its key package when [listsKeyPackage] and without one otherwise; its
  /// startup has completed and it holds an enrollment service.
  Future<AtClientImpl> enrolled(AtKeysIo inner, RsaKeyPair apkam,
      {bool listsKeyPackage = true}) async {
    final client = Completer<AtClient>();
    final created = await AtClientImpl.create(
      atSign,
      'buzz',
      // NOTE: an rsa2048 floor with the post-quantum providers on and seeding
      // set on the preference, so the rsa2048 enrollment seeds without
      // retrofitting.
      AtClientPreference(
          posture: PqPosture(
        authenticationKeyAlgorithm: SigningAlgoType.rsa2048,
        dataSigningKeyAlgorithms: const {},
        seedNamespaceKeys: false,
        keyExchangeMode: EnrollmentKeyExchangeMode.legacy,
        writesPqByDefault: false,
        configuresPqProviders: true,
        disallowLegacyEncryption: false,
        mintLegacyMaterial: true,
        sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
        keyEstablishmentAlgorithms: const [SecretSharingAlgos.xWing],
      ))
        ..hiveStoragePath = storageDir
        ..seedNamespaceKeys = true,
      lookUps: secureSocketLookUps(),
      secondaryAddressFinder: defaultAtDirectory,
      remoteSecondary: buildRecordingRemote(
          events: events,
          remoteData: remoteData,
          remoteMeta: remoteMeta,
          enrollments: {
            'e1.new.enrollments.__manage$atSign': {
              'appName': 'buzz',
              'deviceName': 'pixel',
              'namespace': {'buzz': 'rw'},
              'status': 'approved',
            }
          },
          // NOTE: the roster lists this enrollment with the key package it
          // registered, which the directory verifies against its `_apsk`.
          listns: (namespace) async => [
                {
                  'enrollmentId': 'e1',
                  'access': 'rw',
                  'apkamPubKey': apkam.atPublicKey.publicKey,
                  'metadata': {
                    if (listsKeyPackage)
                      'keyPackage': (await AtClientSecretSharing.forClient(
                                  await client.future)
                              .signedKeyPackagePayload())
                          .toJson()
                  },
                }
              ]),
      atKeysIo: inner, storage: hiveStoreAt(atSign, storageDir),
    );
    client.complete(created);
    // NOTE: the service a factory-built client is given, set by hand here; the
    // startup's own seeding pass ran without it.
    created.enrollmentService =
        EnrollmentServiceImpl(created, AtEnrollment.create());
    await (created as AtClientImpl).pqBootstrap!.startupComplete;
    return created;
  }

  Future<({AtKeysIo inner, RsaKeyPair apkam})> keyfile() async {
    final apkam = RsaKeyPair.generate();
    return (
      inner: await keyfileHolding(atSign,
          encryptionKeyPair: RsaKeyPair.generate(),
          selfEncryptionKey: AESKey.generate(32).key,
          enrollmentId: 'e1',
          apkamKeyPair: apkam),
      apkam: apkam,
    );
  }

  test('the seeded private is in the keyfile by the time peers can seal to it',
      () async {
    final (:inner, :apkam) = await keyfile();
    final created = await enrolled(inner, apkam);
    // NOTE: driven once more, now that the client holds its service.
    await created.pqBootstrap!.seeding.seed();

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

  group('Given an enrollment asked to make its atSign reachable', () {
    test(
        'when its roster entry carries a key package, then its startup has '
        'published and it is already reachable — the control', () async {
      final (:inner, :apkam) = await keyfile();
      final created = await enrolled(inner, apkam);

      final reach = await created.ensureReachable('buzz');

      expect(reach.outcome, AtReachability.alreadyReachable);
      expect(reach.holdsPrivate, isTrue);
      expect(events.where((e) => e.startsWith('update:public:__nskey.buzz')),
          hasLength(1),
          reason: 'the same fixture as below, but for the key package, mints');
    });

    test(
        'when its roster entry carries none, then it answers noKeyPackage and '
        'publishes nothing', () async {
      final (:inner, :apkam) = await keyfile();
      final created = await enrolled(inner, apkam, listsKeyPackage: false);

      expect((await created.ensureReachable('buzz')).outcome,
          AtReachability.noKeyPackage);
      expect(events.where((e) => e.startsWith('update:public:__nskey.buzz')),
          isEmpty,
          reason: 'no other enrollment could be conveyed the private, so '
              'nothing is published for peers to seal to');
    });
  });
}
