// The substrate and the nskey filing surface are both @experimental. Driving
// them from another package is the point of this file.
// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// A conveyed nskey private reaching the keyfile, against a live atServer.
///
/// This is the arrival half of the substrate, and until this file existed it
/// had none: the filer's only entry point was a `receivedSecrets` subscription
/// with no production caller, so a private sent to an enrollment reached its
/// in-memory transit buffer and never its `AtKeys` — and was gone at restart,
/// taking with it every value the content keys it opens protect.
///
/// Three things have to hold at once for this to work, and the test asserts
/// each rather than only the end state, because any one of them failing
/// silently leaves the others looking correct:
///
/// - the running client's key package is the one in its keyfile (otherwise it
///   scans for an address nobody writes to);
/// - a sweep runs (the transit buffer is in memory, and nothing else fills it);
/// - the filer moves the material into `AtKeys`.
void main() {
  late AtClient atClient;
  late String atSign;
  const namespace = 'wavi';

  // A real 32-byte X-Wing seed, not arbitrary bytes: what is filed is a seed
  // now, and NskeyPrivateFiling.read expands it into the decapsulation key the
  // caller actually uses. Arbitrary bytes read back as null, correctly — they
  // are not a key for anything.
  final privateBytes = Uint8List.fromList(List<int>.generate(32, (i) => i));

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final manager = await TestUtils.initAtClient(atSign, namespace);
    atClient = manager.atClient;
  });

  /// A keyfile shaped like one an enrollment made with
  /// `enrollmentKeyPackageBuilder` leaves behind: both halves of one X-Wing
  /// keypair, filed under the kpid they address.
  Future<(InMemoryAtKeysIo, String)> keyfileWithPackage() async {
    final pair = await XWingPureDartAlgo.instance.generateKeyPair();
    final kpid = PackageKey.computeKid(base64Encode(pair.publicKey));
    final now = DateTime.now().toUtc();
    final keys = AtKeys();
    keys.addKey(AtKeysMaterial(
      keyId: kpid,
      keyPartType: CryptographicKeyType.publicEncapsulation,
      keyAlgorithmType: KeyAlgorithmType.xWing,
      bytes: AtBytes(pair.publicKey),
      createdAt: now,
    ));
    keys.addKey(AtKeysMaterial(
      keyId: kpid,
      keyPartType: CryptographicKeyType.privateDecapsulation,
      keyAlgorithmType: KeyAlgorithmType.xWing,
      bytes: AtBytes(pair.secretKey),
      createdAt: now,
    ));
    final io = InMemoryAtKeysIo();
    await io.write(atSign, keys);
    return (io, kpid);
  }

  /// A second identity over the same client, standing in for another of this
  /// atSign's enrollments. `forClient` caches one instance per `AtClient` — it
  /// is the receiver here — so a sender has to use the plain constructor.
  Future<AtClientSecretSharing> sender() async {
    final party = AtClientSecretSharing(atClient)
      ..sendWakeUpNotification = false;
    await party.register();
    return party;
  }

  Secret nskeySecret(String kid) => Secret(
        namespace: namespace,
        name: '${NskeyPrivateFiling.secretNamePrefix}$kid',
        value: base64Encode(privateBytes),
      );

  test('a conveyed private is swept off the atServer and filed into the keyfile',
      () async {
    final (io, advertised) = await keyfileWithPackage();
    final from = await sender();

    // The first collection registers the receiver against the keyfile and
    // sweeps an empty atServer. Both matter: without the binding the receiver
    // would listen on a kpid of its own invention.
    expect(await collectConveyedKeyMaterial(atClient, io), 0);

    final receiver = AtClientSecretSharing.forClient(atClient);
    expect(receiver.kpid, advertised,
        reason: 'the receiver has to be listening on the address its keyfile '
            'advertises, or the rest of this test would be sending to one '
            'party and sweeping for another');
    expect(await NskeyPrivateFiling(keysIo: io, atSign: atSign).read(
            namespace, 'kid-live'),
        isNull,
        reason: 'nothing has been conveyed yet, so a pass here would mean the '
            'assertion below is measuring leftover state');

    await from.shareSecretWith(receiver.myKeyPackage, nskeySecret('kid-live'));

    expect(await collectConveyedKeyMaterial(atClient, io), 1);

    // Read back through a filer built fresh from the same keyfile: what the
    // restart the whole change exists for would see.
    expect(
        await NskeyPrivateFiling(keysIo: io, atSign: atSign)
            .read(namespace, 'kid-live'),
        privateBytes,
        reason: 'the private has to be in AtKeys, not in the transit buffer — '
            'the buffer is in memory and does not survive the process');
  });

  test('a private addressed to another key package is not filed', () async {
    final (io, _) = await keyfileWithPackage();
    final from = await sender();
    final elsewhere = await sender();
    final receiver = AtClientSecretSharing.forClient(atClient);

    // Both arms in one collection, so the negative cannot pass for the wrong
    // reason: if nothing were swept at all, the positive arm would fail too.
    await from.shareSecretWith(receiver.myKeyPackage, nskeySecret('kid-mine'));
    await from.shareSecretWith(
        elsewhere.myKeyPackage, nskeySecret('kid-elsewhere'));

    await collectConveyedKeyMaterial(atClient, io);

    final filed = NskeyPrivateFiling(keysIo: io, atSign: atSign);
    expect(await filed.read(namespace, 'kid-mine'), privateBytes,
        reason: 'the sweep has to have run for the absence below to mean '
            'anything about addressing');
    expect(await filed.read(namespace, 'kid-elsewhere'), isNull,
        reason: 'an envelope is sealed to one key package; a client that filed '
            'what it could merely see would be claiming key material it '
            'cannot open');
  });
}
