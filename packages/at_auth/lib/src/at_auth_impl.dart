import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:at_auth/src/at_auth.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/models/at_auth_responses.dart';
import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/at_keys_io.dart';
import 'package:at_auth/src/keys/at_keys_io_impl.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';

class AtAuthImpl implements AtAuth {
  final AtSignLogger _logger = AtSignLogger('AtAuthServiceImpl');
  final StreamController<ProgressEvent> _progressController =
      StreamController<ProgressEvent>.broadcast();

  ///Progress stream to listen to onboarding/authentication progress.
  @override
  Stream<ProgressEvent> get progressStream => _progressController.stream;
  void _addProgress(String group, String message, ProgressEventType type) {
    var progressEvent = ProgressEvent(group: group, msg: message, type: type);
    _progressController.add(progressEvent);
  }

  @override
  AtChops? atChops;

  CramAuthenticator? cramAuthenticator;

  PkamAuthenticator? pkamAuthenticator;

  AtEnrollment atEnrollment;

  @visibleForTesting
  AtServerStatus? atServerStatus;

  @visibleForTesting
  SecondaryAddressFinder? secondaryAddressFinder;

  @visibleForTesting
  Future<void> Function(String host, int port)? probeSocket;

  @override
  AtLookUp? atLookUp;

  AtAuthImpl(
      {this.atLookUp,
      this.atChops,
      this.cramAuthenticator,
      this.pkamAuthenticator,
      this.atServerStatus,
      AtEnrollment? atEnrollment})
      : atEnrollment = atEnrollment ?? AtEnrollment.create();

  @override

  /// Authenticate using PKAM
  /// The AtAuthRequest must contain either:
  /// - 1. atAuthRequest.atKeysIo - An implementation of AtKeysIo to read the keys
  /// - 2. atAuthRequest.atAuthKeys - An instance of AtKeys containing the keys
  ///
  /// If both are provided, atAuthRequest.atAuthKeys will be used.
  ///
  /// The AtAuthRequest may optionally contain:
  /// - atAuthRequest.enrollmentId - The enrollmentId to use for authentication.
  ///   If not provided, the enrollmentId in the AtAuthKeys will be used.
  /// - atAuthRequest.encryptedKeysMap - Provide the contents of atKeys file which
  ///    contains keys in encrypted format (LEGACY)
  ///
  /// returns an `AtAuthResponse` indicating success or failure of authentication
  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest) async {
    AtKeys? atAuthKeys = atAuthRequest.atAuthKeys;
    await validateAtServer(atAuthRequest);
    try {
      atAuthKeys ??= await atAuthRequest.atKeysIo!.read(atAuthRequest.atSign);
    } on AtKeyException catch (e) {
      _addProgress(
        "authentication",
        "Unable to read keys for atSign: ${atAuthRequest.atSign}",
        ProgressEventType.error,
      );
      throw AtAuthenticationException(
        'Unable to read keys for atSign: ${atAuthRequest.atSign} | Cause: ${e.message}',
      );
    }

    atAuthRequest.enrollmentId ??= atAuthKeys.enrollmentId;
    atLookUp ??= AtLookupImpl(
      atAuthRequest.atSign,
      atAuthRequest.rootDomain.rootDomain,
      atAuthRequest.rootDomain.rootPort,
    );
    // ??= to support mocking
    atChops ??= atAuthKeys.toAtChops();
    atLookUp!.atChops = atChops;

    _logger.finer('Authenticating using PKAM');
    pkamAuthenticator ??= PkamAuthenticator();
    var pkamResponse = AtAuthResponse(atAuthRequest.atSign);
    try {
      pkamResponse
        ..isSuccessful = (await pkamAuthenticator!.authenticate(
            atAuthRequest.atSign, atLookUp!,
            enrollmentId: atAuthRequest.enrollmentId))
        ..atAuthKeys = atAuthKeys
        ..atLookUp = atLookUp
        ..atChops = atChops;

      if (!pkamResponse.isSuccessful) {
        _addProgress(
          "authentication",
          "PKAM authentication failed for atSign: ${atAuthRequest.atSign}",
          ProgressEventType.error,
        );
      } else {
        _addProgress(
          "authentication",
          "PKAM authentication successful for atSign: ${atAuthRequest.atSign}",
          ProgressEventType.success,
        );
      }
    } catch (e, s) {
      _addProgress(
        "authentication",
        "PKAM authentication failed for atSign: ${atAuthRequest.atSign}",
        ProgressEventType.error,
      );
      throw AtAuthenticationException(
          'Unable to authenticate | Cause: $e \n $s');
    }

    return pkamResponse;
  }

  /// Keep some state so callers can call [completeActivation] later
  late AtKeys _atAuthKeys;
  late AtOnboardingRequest _atOnboardingRequest;

  /// Onboard a new atSign using CRAM
  /// Requires an AtOnboardingRequest and a cramSecret
  ///
  /// returns an `AtOnboardingResponse` indicating success or failure of onboarding
  @override
  Future<AtOnboardingResponse> onboard(
    AtOnboardingRequest atOnboardingRequest,
    String cramSecret, {
    bool autoCompleteActivation = true,
    String? publicKeyId,
  }) async {
    var atOnboardingResponse = AtOnboardingResponse(atOnboardingRequest.atSign);
    atLookUp ??= AtLookupImpl(
      atOnboardingRequest.atSign,
      atOnboardingRequest.rootDomain.rootDomain,
      atOnboardingRequest.rootDomain.rootPort,
    );

    //If the user is providing atKeysIo, they might be onboarding again or with a specific key implementation.
    try {
      atOnboardingRequest.atKeys = await atOnboardingRequest.atKeysIo?.read(
        atOnboardingRequest.atSign,
      );
    } catch (e, _) {
      _logger.info(
        'Failed to read keys for atSign: ${atOnboardingRequest.atSign} | Cause: $e',
      ); //swallow the error, we just want to know if keys exist or not
    }

    if (atOnboardingRequest.atKeys != null) {
      throw AtAuthenticationException(
        'atSign: ${atOnboardingRequest.atSign} is already onboarded. Cannot perform onboarding again.',
      );
    }

    await validateAtServer(atOnboardingRequest);
    //1. cram auth
    cramAuthenticator ??= CramAuthenticator();
    var cramAuthResult = await cramAuthenticator!.authenticate(
      atOnboardingRequest.atSign,
      cramSecret,
      atLookUp!,
    );
    if (!cramAuthResult) {
      _addProgress(
        "onboarding",
        "CRAM authentication failed for atSign: ${atOnboardingRequest.atSign}",
        ProgressEventType.error,
      );
      throw AtAuthenticationException(
        'Cram authentication failed. Please check the cram key'
        ' and try again (or) contact support@atsign.com',
      );
    }
    //2. generate key pairs
    if (atOnboardingRequest.atKeys != null) {
      _atAuthKeys = atOnboardingRequest.atKeys!;
    } else {
      //2a. if there is no specified implementation we're defaulting to FileAtKeysIo with a default file path
      atOnboardingRequest.atKeysIo ??= FileAtKeysIo();
      switch (atOnboardingRequest.atKeysIo) {
        case WrittenAtKeysIo writtenKeys:
          _atAuthKeys =
              writtenKeys.generateKeyPairs(atSign: atOnboardingRequest.atSign);
        default:
          throw AtAuthenticationException(
              'AtKeysIo implementation does not support key pair generation, please provide AtKeys in AtOnboardingRequest');
      }
    }
    atChops ??= _atAuthKeys.toAtChops();
    atLookUp!.atChops = atChops;

    //3. send onboarding enrollment
    String? enrollmentIdFromServer;
    // server will update the apkam public key during enrollment.
    // So don't have to manually update apkam public key in this scenario.
    enrollmentIdFromServer = await _sendOnboardingEnrollment(
      atOnboardingRequest,
      _atAuthKeys,
      atLookUp!,
    );
    _atAuthKeys.enrollmentId = enrollmentIdFromServer;

    //4. Close connection to server
    try {
      await (atLookUp as AtLookupImpl).close();
    } on Exception catch (e) {
      _logger.severe('error while closing connection to server: $e');
    }

    //6. Do pkam auth
    pkamAuthenticator ??= PkamAuthenticator();
    try {
      var pkamResponse = await pkamAuthenticator!.authenticate(
          atOnboardingRequest.atSign, atLookUp!,
          enrollmentId: enrollmentIdFromServer);
      if (!pkamResponse) {
        _addProgress(
            "onboarding",
            "PKAM authentication failed for atSign: ${atOnboardingRequest.atSign}",
            ProgressEventType.error);
        throw AtAuthenticationException('Pkam auth returned false');
      }
    } on UnAuthenticatedException catch (e) {
      _addProgress(
          "onboarding",
          "PKAM authentication failed for atSign: ${atOnboardingRequest.atSign}",
          ProgressEventType.error);
      throw AtAuthenticationException('Pkam auth failed - $e ');
    }

    //6b. Store the keys
    if (atOnboardingRequest.atKeysIo is WrittenAtKeysIo) {
      try {
        await (atOnboardingRequest.atKeysIo as WrittenAtKeysIo).write(
          atOnboardingRequest.atSign,
          _atAuthKeys,
        );
        _logger.info(
          'Successfully stored keys for atSign: ${atOnboardingRequest.atSign}',
        );
      } on AtKeyException catch (e) {
        _addProgress(
          "onboarding",
          "Unable to store keys for atSign: ${atOnboardingRequest.atSign}",
          ProgressEventType.error,
        );
        throw AtAuthenticationException(
          'Unable to store keys for atSign: ${atOnboardingRequest.atSign} | Cause: ${e.message}',
        );
      } catch (e) {
        _addProgress(
          "onboarding",
          e.toString(),
          ProgressEventType.error,
        );
        throw AtAuthenticationException(
          'Unable to write keys for atSign: ${atOnboardingRequest.atSign} | Cause: $e',
        );
      }
    }

    //7. If so specified (default behaviour) then
    // - set the public encryption key
    // - delete the cram secret from the keystore
    _atOnboardingRequest = atOnboardingRequest;
    if (autoCompleteActivation) {
      await completeActivation();
    }

    atOnboardingResponse
      ..isSuccessful = true
      ..atAuthKeys = _atAuthKeys
      ..atLookUp = atLookUp
      ..atChops = atChops;

    _addProgress(
        "onboarding",
        "Onboarding successful for atSign: ${atOnboardingRequest.atSign}",
        ProgressEventType.success);
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

  Future<String> _sendOnboardingEnrollment(
      AtOnboardingRequest atOnboardingRequest,
      AtKeys atAuthKeys,
      AtLookUp atLookup) async {
    _logger.finer('apkamPublicKey: ${atAuthKeys.apkamPublicKey}');

    FirstEnrollmentRequest firstEnrollmentRequest = FirstEnrollmentRequest(
        atSign: atOnboardingRequest.atSign,
        appName: atOnboardingRequest.appName,
        deviceName: atOnboardingRequest.deviceName,
        apkamPublicKey: atAuthKeys.apkamPublicKey!.toString());

    AtEnrollmentResponse? atEnrollmentResponse;
    try {
      atEnrollmentResponse =
          await atEnrollment.submit(firstEnrollmentRequest, atLookUp!);
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

  Future<void> _defaultProbeSocket(String host, int port) async {
    final socket =
        await SecureSocket.connect(host, port, timeout: Duration(seconds: 5));
    socket.destroy();
  }

  /// Validates the atSign server status depending on whether it's onboarding or authentication.
  ///
  /// For onboarding, it checks that the root server is found, the secondary server is running,
  /// and the atSign is not already activated.
  ///
  /// For authentication, it checks that the root server is found, the secondary server is running,
  /// and the atSign is already activated.
  ///
  /// Throws an [AtException] if any of the checks fail.
  /// Uses retry logic based on the [RetryOptions] provided in the [AuthRequest].
  /// This method is used internally before onboarding or authentication operations.
  @override
  Future<void> validateAtServer(AuthRequest atRequest) async {
    final maxRetries = atRequest.retryOptions.maxRetries;
    final retryDelay = atRequest.retryOptions.retryDelay;
    int retryCount = 0;

    //support mocking
    atServerStatus ??= AtStatusImpl(
      rootUrl: atRequest.rootDomain.rootDomain,
      rootPort: atRequest.rootDomain.rootPort,
    );

    while (retryCount < maxRetries) {
      retryCount++;
      try {
        _addProgress(
            'Find',
            '#[$retryCount/$maxRetries] : looking up ${atRequest.atSign} in atDirectory',
            ProgressEventType.info);

        var atStatus = await atServerStatus!.get(atRequest.atSign);

        // 3 Checks for onboarding:
        //   1. Root server should be found
        //   2. Secondary server should be running
        //   3. atSign should not be activated already
        if (atRequest is AtOnboardingRequest) {
          if (atStatus.rootStatus != RootStatus.found) {
            throw AtException(
                'Could not find root server: ${atRequest.rootDomain.rootDomain}');
          }
          if (atStatus.serverStatus == ServerStatus.error ||
              atStatus.atSignStatus == AtSignStatus.notFound) {
            throw AtException(
                'atSign: ${atRequest.atSign} secondary server is not running. '
                'Cannot perform onboarding. ${atStatus.serverStatus} ${atStatus.atSignStatus}');
          }
          if (atStatus.atSignStatus == AtSignStatus.activated) {
            throw AtException(
                'atSign: ${atRequest.atSign} is already onboarded. Cannot perform onboarding again.');
          }
        }

        // 3 Checks for authentication:
        //   1. Root server should be found
        //   2. Secondary server should be running
        //   3. atSign should be activated already
        else if (atRequest is AtAuthRequest) {
          if (atStatus.rootStatus == RootStatus.notFound ||
              atStatus.rootStatus == RootStatus.error) {
            throw AtException(
                'Could not find root server: ${atRequest.rootDomain.rootDomain}');
          }
          if (atStatus.serverStatus == ServerStatus.stopped ||
              atStatus.serverStatus == ServerStatus.error ||
              atStatus.serverStatus == ServerStatus.unavailable) {
            throw AtException(
                'atSign: ${atRequest.atSign} secondary server is not running. Cannot perform Authentication.');
          }
          if (atStatus.atSignStatus == AtSignStatus.teapot ||
              atStatus.serverStatus == ServerStatus.teapot) {
            throw AtException(
                'atSign: ${atRequest.atSign} has not been onboarded. Cannot perform Authentication.');
          }
        }

        // AtServer availability probing
        _addProgress(
            'Connect',
            '#[$retryCount/$maxRetries] : Connecting to ${atRequest.atSign} atServer',
            ProgressEventType.info);

        secondaryAddressFinder ??= CacheableSecondaryAddressFinder(
          atRequest.rootDomain.rootDomain,
          atRequest.rootDomain.rootPort,
        );
        SecondaryAddress secondaryAddress =
            await secondaryAddressFinder!.findSecondary(atRequest.atSign);

        await (probeSocket ?? _defaultProbeSocket)(
            secondaryAddress.host, secondaryAddress.port);

        _addProgress(
            'Connect',
            '#[$retryCount/$maxRetries] : Connected to ${atRequest.atSign} atServer',
            ProgressEventType.success);

        break; // Exit loop if no exception occurs
      } catch (e) {
        _logger.severe('Error during atServer validation: $e');
        if (retryCount >= maxRetries) {
          _addProgress('Connect', '#[$retryCount/$maxRetries] : $e',
              ProgressEventType.error);
          throw AtAuthenticationException(
              'Max retries reached while validating atSign server. Last error: $e');
        }
        _logger.warning(
            'Attempt $retryCount failed: $e. Retrying... $retryCount/$maxRetries');
        _addProgress('Connect', '#[$retryCount/$maxRetries] : $e',
            ProgressEventType.error);
        await Future.delayed(retryDelay); // Wait before retrying
      }
    }
  }
}
