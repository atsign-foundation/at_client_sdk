// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart'
    show MlDsa65KeyPair, MlDsa65PureDartAlgo, RsaKeyPair, SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys;
import 'package:at_commons/at_builders.dart' show EnrollVerbBuilder;
import 'package:mocktail/mocktail.dart';

/// Files a client data signing key of [alg] for [client]'s enrollment and
/// publishes its `_apsk` with every such key it holds, returning the key.
Future<ApkamSigningKeys> withSigningKey(AtClient client,
    {SigningAlgoType alg = SigningAlgoType.rsa2048}) async {
  final String pub, priv;
  if (alg == SigningAlgoType.mldsa65) {
    final pair = await MlDsa65KeyPair.generate();
    (pub, priv) = (pair.atPublicKey.publicKey, pair.atPrivateKey.privateKey);
  } else {
    final pair = RsaKeyPair.generate();
    (pub, priv) = (pair.atPublicKey.publicKey, pair.atPrivateKey.privateKey);
  }
  final atSign = client.getCurrentAtSign()!;
  await (client.atKeysIo! as WrittenAtKeysIo).update(atSign.toAtsign(), (keys) {
    keys.fileSigningMaterial(
        enrollmentId: client.enrollmentId!,
        algorithm: alg == SigningAlgoType.mldsa65
            ? CryptographicMaterialAlgorithm.mlDsa65
            : CryptographicMaterialAlgorithm.rsa2048,
        publicKey: pub,
        privateKey: priv);
    return true;
  });
  await AtClientSecretSharing.forClient(client).publishPublicSigningKey();
  return ApkamSigningKeys(algorithm: alg, publicKey: pub, privateKey: priv);
}

/// A signing root published for [atSign] in [remoteData], its key listed as
/// [status].
typedef PublishedRoot = ({LinkVoucher voucher, String pub, String priv});

/// Publishes a fresh signing root for [atSign] in [remoteData].
Future<PublishedRoot> publishRoot(Map<String, String> remoteData, String atSign,
    {String status = 'active'}) async {
  final pair = await MlDsa65PureDartAlgo().generateKeyPair();
  final pub = base64Encode(pair.publicKey);
  remoteData['public:${PqSigningRoot.recordName}$atSign'] =
      jsonEncode(apskAdvertisement(keys: [
    ApskSigningKey.forPublicKey(
        alg: PqSigningRoot.rootKeyAlgo,
        pub: pub,
        status: KeyEntryStatus.of(status))
  ]));
  return (
    voucher: LinkVoucher.root(
        private: Uint8List.fromList(pair.secretKey),
        kid: publicKeyKidOfBase64(pub)),
    pub: pub,
    priv: base64Encode(pair.secretKey),
  );
}

/// Publishes a signing root for [client]'s atSign in [remoteData] and files
/// its private half, and no public half, in [client]'s keyfile beside what is
/// already there.
Future<PublishedRoot> giveRoot(
    AtClient client, Map<String, String> remoteData) async {
  final atSign = client.getCurrentAtSign()!;
  final root = await publishRoot(remoteData, atSign);
  final io = client.atKeysIo! as WrittenAtKeysIo;
  await io.update(atSign.toAtsign(), (keys) {
    keys.addKey(CryptographicMaterial(
      keyId: '${PqSigningRoot.keyIdPrefixFor(PqSigningRoot.rootKeyAlgoToken)}1',
      role: CryptographicMaterialRole.privateSigning,
      algorithm: CryptographicMaterialAlgorithm.mlDsa65,
      bytes: AtBytes(base64Decode(root.priv)),
      createdAt: DateTime.now().toUtc(),
    ));
    return true;
  });
  return root;
}

/// Answers [client]'s approved-filter `enroll:list` with [records], keyed by
/// enrollment id, as an atServer answers a caller that may approve.
void stubApprovedList(
    AtClient client, String atSign, Map<String, Map<String, Object?>> records) {
  final listCommand = (EnrollVerbBuilder()
        ..operation = EnrollOperationEnum.list
        ..enrollmentStatusFilter = [EnrollmentStatus.approved])
      .buildCommand();
  final secondary = client.getRemoteSecondary()!;
  when(() => secondary.executeCommand(listCommand, auth: true))
      .thenAnswer((_) async => 'data:${jsonEncode({
                for (final entry in records.entries)
                  '${entry.key}.new.enrollments.__manage$atSign': {
                    'status': 'approved',
                    ...entry.value,
                  }
              })}');
}
