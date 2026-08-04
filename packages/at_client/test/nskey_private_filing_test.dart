import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:test/test.dart';

/// Moving an arriving nskey private out of the transit buffer and into AtKeys.
///
/// The distinction being enforced is between material that can be recovered
/// and material that cannot. A content key is a cache — a reader re-fetches it
/// from its conveyance record. An nskey private is not: lose it and every
/// conveyance record sealed to it is unopenable, taking every value those
/// content keys protect with it. So it belongs where the never-lose contract
/// is, not in a store an app might persist however it likes.
void main() {
  const atSign = '@alice';
  const namespace = 'app_1.my_apps';

  final privateBytes = Uint8List.fromList(List<int>.generate(64, (i) => i));

  Future<(InMemoryAtKeysIo, NskeyPrivateFiling)> filing() async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    return (io, NskeyPrivateFiling(keysIo: io, atSign: atSign));
  }

  Secret nskeySecret(String kid, {String? ns}) => Secret(
        namespace: ns ?? namespace,
        name: '${NskeyPrivateFiling.secretNamePrefix}$kid',
        value: base64Encode(privateBytes),
      );

  test('an arriving private is filed into AtKeys, keyed by namespace and kid',
      () async {
    final (io, filer) = await filing();

    expect(await filer.file(nskeySecret('kid-one')), isTrue);

    final keys = await io.read(atSign);
    final material = keys.getKey(
        NskeyPrivateFiling.keyIdFor(namespace, 'kid-one'),
        CryptographicKeyType.privateDecapsulation);
    expect(material, isNotNull,
        reason: 'this is the only copy that survives a restart — the transit '
            'store is in-memory by design');
    expect(material!.bytes.bytes, privateBytes);
    expect(material.keyAlgorithmType, KeyAlgorithmType.xWing);
  });

  test('the same kid in two namespaces files as two keys', () async {
    final (io, filer) = await filing();

    await filer.file(nskeySecret('shared-kid'));
    await filer.file(nskeySecret('shared-kid', ns: 'other'));

    final keys = await io.read(atSign);
    expect(
        keys.getKey(NskeyPrivateFiling.keyIdFor(namespace, 'shared-kid'),
            CryptographicKeyType.privateDecapsulation),
        isNotNull);
    expect(
        keys.getKey(NskeyPrivateFiling.keyIdFor('other', 'shared-kid'),
            CryptographicKeyType.privateDecapsulation),
        isNotNull,
        reason: 'kids are truncated hashes and are not unique across '
            'namespaces, so keying on the kid alone would let one namespace '
            'private silently displace another');
  });

  test('a re-delivered private is not filed twice', () async {
    final (_, filer) = await filing();

    expect(await filer.file(nskeySecret('kid-one')), isTrue);
    expect(await filer.file(nskeySecret('kid-one')), isFalse,
        reason: 'the substrate converges by re-sending, so arrival has to be '
            'idempotent — AtKeys.addKey rejects a duplicate outright');
  });

  test('a private with no kid in its name is refused', () async {
    final (io, filer) = await filing();

    expect(
        await filer.file(Secret(
            namespace: namespace,
            name: NskeyPrivateFiling.secretNamePrefix,
            value: base64Encode(privateBytes))),
        isFalse,
        reason: 'without a kid there is no way to tell which generation it '
            'opens, and filing it under a guess would be worse than refusing');
    expect((await io.read(atSign)).keys, isEmpty);
  });

  test('a private that does not derive the published public half is refused',
      () async {
    final real = await XWingKeyPair.generate();
    final other = await XWingKeyPair.generate();
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    final filer = NskeyPrivateFiling(
      keysIo: io,
      atSign: atSign,
      publishedPublicKey: (_, __) async => real.publicKeyBytes,
    );

    // Genuinely signed by this atSign, and genuinely an nskey private — just
    // not the one peers are sealing to. Only correspondence catches that.
    expect(
        await filer.file(Secret(
            namespace: namespace,
            name: '${NskeyPrivateFiling.secretNamePrefix}kid-x',
            value: base64Encode(other.privateKeyBytes))),
        isFalse,
        reason: 'filing it would leave this client believing it can open a '
            'namespace it cannot, and the failure would surface later on data '
            'as corruption rather than as a bad key');
    expect((await io.read(atSign)).keys, isEmpty);
  });

  test('the matching private is accepted', () async {
    final real = await XWingKeyPair.generate();
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    final filer = NskeyPrivateFiling(
      keysIo: io,
      atSign: atSign,
      publishedPublicKey: (_, __) async => real.publicKeyBytes,
    );

    expect(
        await filer.file(Secret(
            namespace: namespace,
            name: '${NskeyPrivateFiling.secretNamePrefix}kid-x',
            value: base64Encode(real.privateKeyBytes))),
        isTrue,
        reason: 'an X-Wing secret key is its seed, so the public half derives '
            'from it exactly — the check is precise, not heuristic');
  });

  test('only nskey privates are filed; other secrets pass through', () async {
    final (io, filer) = await filing();

    expect(
        await filer.filePending([
          Secret(namespace: namespace, name: 'an-app-token', value: 'v'),
          nskeySecret('kid-two'),
        ]),
        1);

    final keys = await io.read(atSign);
    expect(keys.keys, hasLength(1),
        reason: 'the substrate carries opaque secrets and this only claims its '
            'own — an app secret is none of the crypto layer\'s business');
    expect(
        keys.getKey(NskeyPrivateFiling.keyIdFor(namespace, 'kid-two'),
            CryptographicKeyType.privateDecapsulation),
        isNotNull);
  });

  test('every conveyed generation is filed, not just the newest', () async {
    final (io, filer) = await filing();

    expect(
        await filer.filePending(
            [nskeySecret('gen-one'), nskeySecret('gen-two')]),
        2,
        reason: 'data written under a superseded key is still readable, and '
            'only its own private opens it — a client given the current '
            'generation alone could read nothing written before the last '
            'rotation');
    expect(await filer.readAllFor(namespace), hasLength(2));
  });

  test('re-draining the same store files nothing twice', () async {
    final (_, filer) = await filing();
    final held = [nskeySecret('kid-three')];

    expect(await filer.filePending(held), 1);
    expect(await filer.filePending(held), 0,
        reason: 'the substrate converges by re-sending, so the same secret is '
            'drained at every start; filing is idempotent on the keyfile');
  });
}
