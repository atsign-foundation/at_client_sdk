import 'package:at_client/at_client.dart'
    show
        AtClient,
        AtKeyNotFoundException,
        AtKey,
        GetRequestOptions,
        PutRequestOptions;
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys, apskUri;
import 'package:at_utils/at_utils.dart' show AtSignLogger;

mixin ApkamSigning {
  AtClient get atClient;

  AtSignLogger get logger;

  String get enrollmentId {
    String id =
        atClient.getRemoteSecondary()?.atLookUp.enrollmentId ?? 'primary';
    if (id == 'primary') {
      logger.warning('No enrollmentID ... using "primary"');
    }
    return id;
  }

  /// the uri (e.g. `public:_apsk.<enrollment_id>.a.__e@atsign`) of the
  /// [publicSigningKey]
  String get publicSigningKeyUri =>
      apskUri(atClient.getCurrentAtSign()!, enrollmentId);

  Future publishPublicSigningKey() async {
    try {
      logger.info('publishPublicSigningKey: checking $publicSigningKeyUri');
      await atClient.get(
        AtKey.fromString(publicSigningKeyUri),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      logger.info('publishPublicSigningKey: have already published');
    } on AtKeyNotFoundException catch (err) {
      logger.info('${err.message} - publishing now');
      await atClient.put(
        AtKey.fromString(publicSigningKeyUri),
        publicSigningKey,
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
      );
    }
  }

  /// This client's APKAM key material, as an argument for the signing
  /// functions rather than state reached out of a crypto object.
  ///
  /// The material is still read from `atClient.atChops` here. That is a
  /// derived cache, not the source: when an `AtKeysIo` is injected, the
  /// client already builds its `AtChops` from the `AtKeys` that `AtKeysIo`
  /// reads. Sourcing this from `AtKeys` directly is the remaining half of the
  /// move, and it cannot land until every client has an `AtKeysIo` — today it
  /// is nullable and most apps supply none, so reading through it would break
  /// them.
  ApkamSigningKeys get signingKeys {
    final keyPair = atClient.atChops!.atChopsKeys.atPkamKeyPair!;
    return ApkamSigningKeys(
      publicKey: keyPair.atPublicKey.publicKey,
      privateKey: keyPair.atPrivateKey.privateKey,
    );
  }

  /// the public key which can be used to verify signatures made using
  /// [signingKeys]
  String get publicSigningKey => signingKeys.publicKey;
}
