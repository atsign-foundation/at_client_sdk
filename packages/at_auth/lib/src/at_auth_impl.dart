import 'package:at_auth/src/at_auth_base.dart';
import 'package:at_auth/src/auth/at_auth_request.dart';
import 'package:at_auth/src/auth/at_auth_response.dart';
import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/at_enrollment_base.dart';
import 'package:at_auth/src/enroll/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/first_enrollment_request.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/at_keys_io.dart';
import 'package:at_auth/src/keys/at_keys_io_impl.dart';
import 'package:at_auth/src/onboard/at_onboarding_request.dart';
import 'package:at_auth/src/onboard/at_onboarding_response.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

class AtAuthImpl implements AtAuth {
  final AtSignLogger _logger = AtSignLogger('AtAuthServiceImpl');
  final String _defaultAppNameForOnboarding = 'firstApp';
  final String _defaultDeviceNameForOnboarding = 'firstDevice';
  @override
  AtChops? atChops;

  CramAuthenticator? cramAuthenticator;

  PkamAuthenticator? pkamAuthenticator;

  AtEnrollmentBase atEnrollmentBase;

  @override
  AtLookUp? atLookUp;

  AtAuthImpl(
      {this.atLookUp,
      this.atChops,
      this.cramAuthenticator,
      this.pkamAuthenticator,
      AtEnrollmentBase? atEnrollmentBase})
      : atEnrollmentBase = atEnrollmentBase ?? AtEnrollmentBase.create();

  @override

  /// Authenticate using PKAM
  /// The AtAuthRequest must contain either:
  /// - 1. atAuthRequest.atKeysIo - An implementation of AtKeysIo to read the keys
  /// - 2. atAuthRequest.atAuthKeys - An instance of AtKeys containing the keys
  /// - 3. atAuthRequest.encryptedKeysMap - Provide the contents of atKeys file which
  ///    contains keys in encrypted format
  ///
  /// The AtAuthRequest may optionally contain:
  /// - atAuthRequest.enrollmentId - The enrollmentId to use for authentication.
  ///   If not provided, the enrollmentId in the AtAuthKeys will be used.
  ///
  /// returns an `AtAuthResponse` indicating success or failure of authentication
  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest) async {
    if (atAuthRequest.atKeysIo == null && atAuthRequest.atAuthKeys == null) {
      throw AtAuthenticationException(
          'atKeysIO implementation is required to read keys, either provide atKeysIO implementation'
          ' or provide atAuthKeys in the AtAuthRequest');
    }
    AtKeys? atAuthKeys = atAuthRequest.atAuthKeys;
    if (atAuthKeys == null && atAuthRequest.atKeysIo != null) {
      try {
        atAuthKeys = await atAuthRequest.atKeysIo!.read(atAuthRequest.atSign);
      } on AtKeyException catch (e) {
        throw AtAuthenticationException(
            'Unable to read keys for atSign: ${atAuthRequest.atSign} | Cause: ${e.message}');
      }
    } else if (atAuthKeys == null) {
      throw AtAuthenticationException(
          'atKeysIO implementation is required to read keys, either provide atKeysIO implementation'
          ' or provide atAuthKeys in the AtAuthRequest');
    }
    if (atAuthKeys.apkamPrivateKey == null ||
        atAuthKeys.apkamPrivateKey!.toString().isEmpty) {
      throw AtPrivateKeyNotFoundException(
          'apkamPrivateKey is null or empty in atAuthKeys');
    }
    var enrollmentIdFromRequest = atAuthRequest.enrollmentId;
    enrollmentIdFromRequest ??= atAuthKeys.enrollmentId;

    atAuthKeys.enrollmentId = enrollmentIdFromRequest;
    atLookUp ??= AtLookupImpl(atAuthRequest.atSign,
        atAuthRequest.rootDomain.rootDomain, atAuthRequest.rootDomain.rootPort);
    // ??= to support mocking
    atChops ??= _createAtChops(atAuthKeys);
    atLookUp!.atChops = atChops;

    _logger.finer('Authenticating using PKAM');
    var isPkamAuthenticated = false;
    pkamAuthenticator ??= PkamAuthenticator(atAuthRequest.atSign, atLookUp!);
    try {
      var pkamResponse = (await pkamAuthenticator!
          .authenticate(enrollmentId: enrollmentIdFromRequest));
      isPkamAuthenticated = pkamResponse.isSuccessful;
    } on AtException catch (e) {
      _logger.severe('Caught $e');
      throw AtAuthenticationException(
          'Unable to authenticate | Cause: ${e.message}');
    } on Exception catch (e) {
      throw AtAuthenticationException('Unable to authenticate | Cause: $e');
    }
    _logger.finer(
        'PKAM auth result: ${isPkamAuthenticated ? 'success' : 'failed'}');
    return AtAuthResponse(atAuthRequest.atSign)
      ..isSuccessful = isPkamAuthenticated
      ..enrollmentId = enrollmentIdFromRequest
      ..atAuthKeys = atAuthKeys;
  }

  /// Keep some state so callers can call [completeActivation] later
  late AtKeys _atAuthKeys;
  late AtOnboardingRequest _atOnboardingRequest;

  @override
  Future<AtOnboardingResponse> onboard(
    AtOnboardingRequest atOnboardingRequest,
    String cramSecret, {
    bool autoCompleteActivation = true,
    String? publicKeyId,
  }) async {
    _atOnboardingRequest = atOnboardingRequest;
    var atKeysIo = atOnboardingRequest.atKeysIo;
    var atOnboardingResponse = AtOnboardingResponse(atOnboardingRequest.atSign);
    atLookUp ??= AtLookupImpl(
        atOnboardingRequest.atSign,
        atOnboardingRequest.rootDomain.rootDomain,
        atOnboardingRequest.rootDomain.rootPort);

    //1. cram auth
    cramAuthenticator ??=
        CramAuthenticator(atOnboardingRequest.atSign, cramSecret, atLookUp);
    var cramAuthResult = await cramAuthenticator!.authenticate();
    if (!cramAuthResult.isSuccessful) {
      throw AtAuthenticationException(
          'Cram authentication failed. Please check the cram key'
          ' and try again (or) contact support@atsign.com');
    }
    //2. generate key pairs
    if (atOnboardingRequest.atKeys != null) {
      _atAuthKeys = atOnboardingRequest.atKeys!;
    } else {
      switch (atKeysIo) {
        // case GeneratedAtKeysIo():
        //   if (publicKeyId == null || publicKeyId.isEmpty) {
        //     throw AtAuthenticationException('sim publicKeyId is required for sim auth mode');
        //   }
        //   _atAuthKeys = atKeysIo.generateKeys(publicKeyId);
        //   break;
        case WrittenAtKeysIo():
          // if the atKeysIo is FileAtKeysIo, then generate keys and write to file.
          if (atKeysIo is FileAtKeysIo) {
            _atAuthKeys =
                atKeysIo.generateKeyPairs(atSign: atOnboardingRequest.atSign);
          }
          await atKeysIo.write(atOnboardingRequest.atSign, _atAuthKeys);
          break;
        default:
          throw AtAuthenticationException(
              'Unsupported AtKeysIO implementation: ${atKeysIo.runtimeType}');
      }
    }

    atChops ??= _createAtChops(_atAuthKeys);
    atLookUp!.atChops = atChops;

    //3. send onboarding enrollment
    String? enrollmentIdFromServer;
    // server will update the apkam public key during enrollment.
    // So don't have to manually update apkam public key in this scenario.
    enrollmentIdFromServer = await _sendOnboardingEnrollment(
        atOnboardingRequest, _atAuthKeys, atLookUp!);
    _atAuthKeys.enrollmentId = enrollmentIdFromServer;

    //4. Close connection to server
    try {
      await (atLookUp as AtLookupImpl).close();
    } on Exception catch (e) {
      _logger.severe('error while closing connection to server: $e');
    }

    //5. Init _atLookUp again and attempt pkam auth
    // atLookUp = AtLookupImpl(atOnboardingRequest.atSign,
    //     atOnboardingRequest.rootDomain, atOnboardingRequest.rootPort);
    atLookUp!.atChops = atChops;

    var isPkamAuthenticated = false;
    //6. Do pkam auth
    pkamAuthenticator ??=
        PkamAuthenticator(atOnboardingRequest.atSign, atLookUp!);
    try {
      var pkamResponse = await pkamAuthenticator!
          .authenticate(enrollmentId: enrollmentIdFromServer);
      isPkamAuthenticated = pkamResponse.isSuccessful;
    } on UnAuthenticatedException catch (e) {
      throw AtAuthenticationException('Pkam auth failed - $e ');
    }
    if (!isPkamAuthenticated) {
      throw AtAuthenticationException('Pkam auth returned false');
    }

    //7. If so specified (default behaviour) then
    // - set the public encryption key
    // - delete the cram secret from the keystore
    if (autoCompleteActivation) {
      await completeActivation();
    }

    atOnboardingResponse.isSuccessful = true;
    atOnboardingResponse.enrollmentId = enrollmentIdFromServer;
    atOnboardingResponse.atAuthKeys = _atAuthKeys;

    return atOnboardingResponse;
  }

  @override
  Future<void> completeActivation() async {
    final encryptionPublicKey = _atAuthKeys.defaultEncryptionPublicKey;
    UpdateVerbBuilder updateBuilder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'publickey'
        ..sharedBy = _atOnboardingRequest.atSign
        ..metadata = (Metadata()
          ..isPublic = true
          ..ttr = -1))
      ..value = encryptionPublicKey;
    String? encryptKeyUpdateResult = await atLookUp!.executeVerb(updateBuilder);
    _logger.info('Encryption public key update result $encryptKeyUpdateResult');

    DeleteVerbBuilder deleteBuilder = DeleteVerbBuilder()
      ..atKey = (AtKey()..key = AtConstants.atCramSecret);
    String? deleteResponse = await atLookUp!.executeVerb(deleteBuilder);
    _logger.info('Cram secret delete response : $deleteResponse');
  }

  AtChops _createAtChops(AtKeys atKeysFile) {
    final atEncryptionKeyPair = AtEncryptionKeyPair.create(
        atKeysFile.defaultEncryptionPublicKey!.toString(),
        atKeysFile.defaultEncryptionPrivateKey!.toString());
    final atPkamKeyPair = AtPkamKeyPair.create(
        atKeysFile.apkamPublicKey!.toString(),
        atKeysFile.apkamPrivateKey!.toString());
    final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    if (atKeysFile.apkamSymmetricKey != null) {
      atChopsKeys.apkamSymmetricKey =
          AESKey(atKeysFile.apkamSymmetricKey!.toString());
    }
    atChopsKeys.selfEncryptionKey =
        AESKey(atKeysFile.defaultSelfEncryptionKey!.toString());
    return AtChopsImpl(atChopsKeys);
  }

  Future<String> _sendOnboardingEnrollment(
      AtOnboardingRequest atOnboardingRequest,
      AtKeys atAuthKeys,
      AtLookUp atLookup) async {
    atOnboardingRequest.appName ??= _defaultAppNameForOnboarding;
    atOnboardingRequest.deviceName ??= _defaultDeviceNameForOnboarding;

    _logger.finer('apkamPublicKey: ${atAuthKeys.apkamPublicKey}');

    FirstEnrollmentRequest firstEnrollmentRequest = FirstEnrollmentRequest(
        atSign: atOnboardingRequest.atSign,
        appName: atOnboardingRequest.appName!,
        deviceName: atOnboardingRequest.deviceName!,
        apkamPublicKey: atAuthKeys.apkamPublicKey!.toString());

    AtEnrollmentResponse? atEnrollmentResponse;
    try {
      atEnrollmentResponse =
          await atEnrollmentBase.submit(firstEnrollmentRequest, atLookUp!);
    } on AtEnrollmentException catch (e) {
      throw AtAuthenticationException('Enrollment error:${e.toString}');
    }
    _logger.finer('enrollment response: ${atEnrollmentResponse.toString()}');
    var enrollmentIdFromServer = atEnrollmentResponse.enrollmentId;
    var enrollmentStatus = atEnrollmentResponse.enrollStatus;
    if (enrollmentStatus != EnrollmentStatus.approved) {
      throw AtAuthenticationException(
          'initial enrollment is not approved. Status from server: $enrollmentStatus \n with $atEnrollmentResponse');
    }
    return enrollmentIdFromServer;
  }
}
