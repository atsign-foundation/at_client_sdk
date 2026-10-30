// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/at_lookup_io.dart';
import 'package:at_client_cli/at_client_cli.dart';
import 'package:test/test.dart';

import 'lifecycle_rig.dart';

/// The signer installed on the client's connection has to belong to the
/// enrolment that connection declares: the retrofitted one, not the legacy
/// one the flat fields still carry.
void main() {
  AtSignLogger.root_level = 'SHOUT';

  const atSign = '@retrofitted_cli';
  const namespace = 'unit_test';
  const flatEnrollmentId = 'legacy-flat-enrollment';
  const retrofittedId = 'retrofitted-enrollment';

  late String keysFilePath;
  late Directory storage;

  setUp(() async {
    AtClientImpl.atClientInstanceMap.clear();
    storage = Directory.systemTemp.createTempSync('retrofit_storage');
    keysFilePath =
        '${Directory.systemTemp.createTempSync('retrofit_keys').path}'
        '/${atSign}_key.atKeys';

    // The keyfile a retrofit leaves behind: the legacy enrolment's RSA keypair
    // in the flat fields, the live enrolment's ML-DSA-65 material in the typed
    // section. Both halves are real keys, since the assertion below is a
    // signature that either gets produced or does not.
    final rsaPair = AtChopsUtil.generateAtPkamKeyPair();
    final encryptionPair = AtChopsUtil.generateAtEncryptionKeyPair();
    final mlDsaPair = await MlDsa65KeyPair.generate();
    final now = DateTime.now().toUtc();
    final keys = AtKeys()
      ..enrollmentId = flatEnrollmentId
      ..apkamPublicKey = AtBytes.fromString(rsaPair.atPublicKey.publicKey)
      ..apkamPrivateKey = AtBytes.fromString(rsaPair.atPrivateKey.privateKey)
      // NOTE: `FileAtKeysIo` self-encrypts the legacy fields on write and
      // refuses without the self-encryption key.
      ..defaultEncryptionPublicKey =
          AtBytes.fromString(encryptionPair.atPublicKey.publicKey)
      ..defaultEncryptionPrivateKey =
          AtBytes.fromString(encryptionPair.atPrivateKey.privateKey)
      ..defaultSelfEncryptionKey = AtBytes.fromString(AESKey.generate(32).key)
      ..addKey(CryptographicMaterial(
        keyId: 'auth:mldsa65:1',
        enrollmentId: retrofittedId,
        role: CryptographicMaterialRole.privateAuthentication,
        algorithm: CryptographicMaterialAlgorithm.mlDsa65,
        bytes: AtBytes.fromString(mlDsaPair.atPrivateKey.privateKey),
        createdAt: now,
      ))
      ..addKey(CryptographicMaterial(
        keyId: 'auth:mldsa65:1',
        enrollmentId: retrofittedId,
        role: CryptographicMaterialRole.publicAuthentication,
        algorithm: CryptographicMaterialAlgorithm.mlDsa65,
        bytes: AtBytes.fromString(mlDsaPair.atPublicKey.publicKey),
        createdAt: now,
      ));
    await FileAtKeysIo(filePath: (_) => keysFilePath).write(atSign, keys);
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
    File(keysFilePath).parent.deleteSync(recursive: true);
    storage.deleteSync(recursive: true);
  });

  test('the client\'s connection authenticates as the enrolment it declares',
      () async {
    final port = await refusedPort();
    // NOTE: a real lookup, pointed at a port nothing listens on: the client's
    // connection wraps and stamps it, and the open comes back offline without
    // a network.
    final own = AtLookupImpl(atSign, InternetAddress.loopbackIPv4.address, port,
        secondaryAddressFinder: FixedSecondaryAddressFinder(
            InternetAddress.loopbackIPv4.address, port),
        transportFactory: SecureSocketTransportFactory(
            secureSocketConfig: SecureSocketConfig()));
    final client = await Atsign(atSign).open(
        keys: CliKeys.fileFor(atSign, path: keysFilePath),
        preference: AtClientPreference(posture: PqPosture.legacy)
          ..namespace = namespace
          ..rootDomain = InternetAddress.loopbackIPv4.address
          ..rootPort = port,
        storage:
            CliKeys.storageFor(atSign, program: namespace, path: storage.path),
        atLookUp: own,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: FixedSecondaryAddressFinder(
            InternetAddress.loopbackIPv4.address, port));
    expect(client.connection.current.isOnline, isFalse,
        reason: 'offline by construction; what is under test was installed '
            'when the client was built');

    final adopted = client.getRemoteSecondary()!.atLookUp;
    expect(identical(adopted, own), isTrue,
        reason: 'the client wraps the lookup it was handed; if it built its '
            'own, everything below is about the wrong object');

    final exchange = OfflineExchange(atSign);
    // NOTE: `AtLookUp` does not declare the authenticator — that interface is
    // frozen for the mocks implementing it — so the seam is reached through
    // `AtLookupMuxable`.
    //
    // The completion check alone cannot tell the enrolments apart: the
    // authenticator takes the keypair and the algorithm it declares from one
    // place, so a client resolving the flat enrolment signs RSA and completes
    // too. The client's enrolment and the pkam: it sends say which one it is.
    expect(client.enrollmentId, retrofittedId);
    final authenticator = (adopted as AtLookupMuxable).authenticator!;
    await expectLater(authenticator(exchange), completion(isTrue),
        reason: 'the lookup declares mldsa65 for the retrofitted enrolment, so '
            'the signer installed beside it has to be that enrolment\'s '
            'ML-DSA keypair. Handing it the flat enrolment\'s RSA keypair '
            'reaches at_chops as "this PKAM key is ~1218 bytes, and an '
            'ML-DSA-65 secret key is 4032", and no verb this client runs can '
            'authenticate');

    final pkam = exchange.sent.where((c) => c.startsWith('pkam:'));
    expect(pkam, isNotEmpty,
        reason: 'a green that never reached the pkam: verb would mean the '
            'authenticator short-circuited rather than signed');
    expect(
        pkam,
        everyElement(allOf(contains('signingAlgo:mldsa65'),
            contains(':enrollmentId:$retrofittedId:'))),
        reason: 'the flat enrolment\'s RSA pair also signs, and the exchange '
            'accepts any pkam:, so only the verb shows which one authenticated');
  });
}
