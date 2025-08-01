import 'package:at_client/at_client.dart'
    show
        AtClient,
        EnrollmentConstants,
        AtKeyNotFoundException,
        AtKey,
        GetRequestOptions,
        PutRequestOptions;
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

  /// the uri (e.g. `public:apsk.<enrollment_id>.__wa@atsign`) of the
  /// [publicSigningKey]
  String get publicSigningKeyUri {
    return 'public:'
        '_apsk.$enrollmentId.${EnrollmentConstants.perEnrollmentApproved}'
        '${atClient.getCurrentAtSign()}';
  }

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

  /// the public key which can be used to verify signatures made using
  /// [privateSigningKey]
  String get publicSigningKey {
    return atClient.atChops!.atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey;
  }

  /// the private key used to sign things this application sends
  String get privateSigningKey {
    return atClient.atChops!.atChopsKeys.atPkamKeyPair!.atPrivateKey.privateKey;
  }
}
