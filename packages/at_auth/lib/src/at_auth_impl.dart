import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:at_auth/src/at_auth.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/models/at_auth_session.dart';
import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/io/at_keys_io.dart';
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

  /// Emits a single event to both channels: the [progressStream] and the
  /// [AtSignLogger], so callers listening to either one see it. Errors and
  /// warnings carry their [error]/[stackTrace] into the log record rather than
  /// having them stringified into the message.
  void _progress(
    String group,
    String message,
    ProgressEventType type, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _addProgress(group, message, type);
    switch (type) {
      case ProgressEventType.error:
        _logger.severe(message, error, stackTrace);
      case ProgressEventType.warning:
        _logger.warning(message, error, stackTrace);
      case ProgressEventType.info:
      case ProgressEventType.success:
        _logger.info(message);
    }
  }

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
      this.cramAuthenticator,
      this.pkamAuthenticator,
      this.atServerStatus,
      AtEnrollment? atEnrollment})
      : atEnrollment = atEnrollment ?? AtEnrollment.create();

  @override

  /// Authenticate using PKAM.
  ///
  /// The keys always come from `atAuthRequest.atKeysIo` — an [AtKeysIo]
  /// implementation over a file, keychain, or memory. To authenticate with keys
  /// you already hold, put them in an [InMemoryAtKeysIo].
  ///
  /// Optionally, `atAuthRequest.enrollmentId` selects the enrollment to
  /// authenticate as; when it is null the enrollmentId stored in the keys is
  /// used.
  ///
  /// Returns the [AtAuthSession] to hand to client creation. On failure this
  /// throws [AtAuthenticationException] and closes any connection it opened —
  /// there is no unsuccessful return value.
  Future<AtAuthSession> authenticate(AtAuthRequest atAuthRequest) async {
    _progress(
      "authentication",
      "Authenticating atSign: ${atAuthRequest.atsign}",
      ProgressEventType.info,
    );
    await validateAtServer(atAuthRequest);
    AtKeys atKeys;
    try {
      atKeys = await atAuthRequest.atKeysIo.read(atAuthRequest.atsign);
    } on AtKeyException catch (e, s) {
      _progress(
        "authentication",
        "Unable to read keys for atSign: ${atAuthRequest.atsign}",
        ProgressEventType.error,
        error: e,
        stackTrace: s,
      );
      Error.throwWithStackTrace(
        AtAuthenticationException(
          'Unable to read keys for atSign: ${atAuthRequest.atsign} | Cause: ${e.message}',
        ),
        s,
      );
    }

    atAuthRequest.enrollmentId ??= atKeys.enrollmentId;
    atLookUp ??= AtLookupImpl(
      atAuthRequest.atsign,
      atAuthRequest.rootDomain.rootDomain,
      atAuthRequest.rootDomain.rootPort,
    );

    _logger.finer('Authenticating atSign: ${atAuthRequest.atsign} using PKAM '
        '(enrollmentId: ${atAuthRequest.enrollmentId})');
    pkamAuthenticator ??= PkamAuthenticator();
    try {
      // Throws UnAuthenticatedException on failure; reaching past this call
      // means PKAM succeeded.
      await pkamAuthenticator!.authenticate(
        atAuthRequest.atsign,
        atLookUp!,
        atKeys,
        enrollmentId: atAuthRequest.enrollmentId,
      );

      _progress(
        "authentication",
        "PKAM authentication successful for atSign: ${atAuthRequest.atsign}",
        ProgressEventType.success,
      );
    } catch (e, s) {
      _progress(
        "authentication",
        "PKAM authentication failed for atSign: ${atAuthRequest.atsign}",
        ProgressEventType.error,
        error: e,
        stackTrace: s,
      );
      // A throw here abandons the connection we opened — close it before the
      // error propagates so a failed authenticate doesn't leak the AtLookup.
      await _closeQuietly();
      Error.throwWithStackTrace(
        AtAuthenticationException('Unable to authenticate | Cause: $e'),
        s,
      );
    }
// Build the explicit hand-off session from the request's confirmed subset
    final session = AtAuthSession(
      atsign: atAuthRequest.atsign,
      rootDomain: atAuthRequest.rootDomain,
      namespace: atAuthRequest.namespace,
      atKeysIo: atAuthRequest.atKeysIo,
      enrollmentId: atAuthRequest.enrollmentId,
      atLookUp: atLookUp,
    );
    return session;
  }

  /// Best-effort teardown of [atLookUp] on a failure path, so a throw doesn't
  /// leak the AtLookup we opened. A no-op when [atLookUp] isn't an
  /// [AtLookupImpl] we can close.
  Future<void> _closeQuietly() async {
    if (atLookUp is! AtLookupImpl) {
      return;
    }
    try {
      await (atLookUp as AtLookupImpl).close();
    } catch (_) {
      // cleanup is best-effort
    }
  }

  /// Onboard a new atSign using CRAM.
  ///
  /// Requires an [AtOnboardingRequest] and its one-time [cramSecret]. Mints a
  /// fresh keyset, enrolls it, PKAM-authenticates, and persists the keys
  /// through the request's [AtKeysIo].
  ///
  /// Returns the [AtAuthSession] to hand to client creation. Failure throws —
  /// there is no unsuccessful return value.
  @override
  Future<AtAuthSession> onboard(
    AtOnboardingRequest atOnboardingRequest,
    String cramSecret, {
    bool autoCompleteActivation = true,
    String? publicKeyId,
  }) async {
    _progress(
      "onboarding",
      "Onboarding atSign: ${atOnboardingRequest.atsign}",
      ProgressEventType.info,
    );
    atLookUp ??= AtLookupImpl(
      atOnboardingRequest.atsign,
      atOnboardingRequest.rootDomain.rootDomain,
      atOnboardingRequest.rootDomain.rootPort,
    );

    //1. cram auth
    try {
      await validateAtServer(atOnboardingRequest);
      cramAuthenticator ??= CramAuthenticator();
      try {
        // Throws UnAuthenticatedException on failure.
        await cramAuthenticator!.authenticate(
          atOnboardingRequest.atsign,
          cramSecret,
          atLookUp!,
        );
      } on UnAuthenticatedException catch (e, s) {
        _progress(
          "onboarding",
          "CRAM authentication failed for atSign: ${atOnboardingRequest.atsign}",
          ProgressEventType.error,
          error: e,
          stackTrace: s,
        );
        Error.throwWithStackTrace(
          AtAuthenticationException(
            'Cram authentication failed. Please check the cram key'
            ' and try again (or) contact support@atsign.com',
          ),
          s,
        );
      }
      _progress(
        "onboarding",
        "CRAM authentication successful for atSign: ${atOnboardingRequest.atsign}",
        ProgressEventType.success,
      );

      //2. generate key pairs
      AtKeys atKeys = await AuthBootstrap.bootstrap(atOnboardingRequest.atsign);

      //3. send onboarding enrollment
      String? enrollmentIdFromServer;
      // server will update the apkam public key during enrollment.
      // So don't have to manually update apkam public key in this scenario.
      enrollmentIdFromServer = await _sendOnboardingEnrollment(
        atOnboardingRequest,
        atKeys,
        atLookUp!,
      );
      atKeys.enrollmentId = enrollmentIdFromServer;

      //4. Do pkam auth
      pkamAuthenticator ??= PkamAuthenticator();
      try {
        // Throws UnAuthenticatedException on failure.
        await pkamAuthenticator!.authenticate(
            atOnboardingRequest.atsign, atLookUp!, atKeys,
            enrollmentId: enrollmentIdFromServer);
        _progress(
            "onboarding",
            "PKAM authentication successful for atSign: ${atOnboardingRequest.atsign}",
            ProgressEventType.success);
      } on UnAuthenticatedException catch (e, s) {
        _progress(
            "onboarding",
            "PKAM authentication failed for atSign: ${atOnboardingRequest.atsign}",
            ProgressEventType.error,
            error: e,
            stackTrace: s);
        Error.throwWithStackTrace(
          AtAuthenticationException('Pkam auth failed - $e '),
          s,
        );
      }

      //4b. Store the keys
      try {
        await atOnboardingRequest.atKeysIo.write(
          atOnboardingRequest.atsign,
          atKeys,
        );
        _progress(
          "onboarding",
          "Successfully stored keys for atSign: ${atOnboardingRequest.atsign}",
          ProgressEventType.success,
        );
      } catch (e, s) {
        _progress(
          "onboarding",
          "Unable to store keys for atSign: ${atOnboardingRequest.atsign}",
          ProgressEventType.error,
          error: e,
          stackTrace: s,
        );
        Error.throwWithStackTrace(
          AtAuthenticationException(
            'Unable to store keys for atSign: ${atOnboardingRequest.atsign} | Cause: ${e.toString()}',
          ),
          s,
        );
      }

      // Hand back the same explicit session as authenticate(), so a
      // freshly-onboarded atSign flows straight into the client. atKeysIo is
      // guaranteed set here (defaulted to FileAtKeysIo above); the guard mirrors
      // authenticate() for parity.
      final session = AtAuthSession(
        atsign: atOnboardingRequest.atsign,
        rootDomain: atOnboardingRequest.rootDomain,
        namespace: atOnboardingRequest.namespace,
        atKeysIo: atOnboardingRequest.atKeysIo,
        enrollmentId: enrollmentIdFromServer,
        atLookUp: atLookUp,
      );

      //5. If so specified (default behaviour) then
      // - set the public encryption key
      // - delete the cram secret from the keystore
      if (autoCompleteActivation) {
        await completeActivation(session);
      }

      _progress(
          "onboarding",
          "Onboarding successful for atSign: ${atOnboardingRequest.atsign}",
          ProgressEventType.success);
      return session;
    } catch (e) {
      // Any throw above abandons the AtLookup we opened (the inner catches
      // rethrow into here) — close it before the error propagates so a failed
      // onboard doesn't leak the AtLookup.
      await _closeQuietly();
      rethrow;
    }
  }

  @override
  Future<void> completeActivation(AtAuthSession incompleteSession) async {
    AtKeys atKeys =
        await incompleteSession.atKeysIo.read(incompleteSession.atsign);
    final encryptionPublicKey = atKeys.defaultEncryptionPublicKey;
    UpdateVerbBuilder updateBuilder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'publickey'
        ..sharedBy = incompleteSession.atsign
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
        atSign: atOnboardingRequest.atsign,
        appName: atOnboardingRequest.appName,
        deviceName: atOnboardingRequest.deviceName,
        apkamPublicKey: atAuthKeys.apkamPublicKey!.toString());

    AtEnrollmentResponse? atEnrollmentResponse;
    try {
      atEnrollmentResponse =
          await atEnrollment.submit(firstEnrollmentRequest, atLookUp!);
    } on AtEnrollmentException catch (e, s) {
      _progress(
          "onboarding",
          "Enrollment failed for atSign: ${atOnboardingRequest.atsign}",
          ProgressEventType.error,
          error: e,
          stackTrace: s);
      Error.throwWithStackTrace(
        AtAuthenticationException('Enrollment error: $e'),
        s,
      );
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
    // Floor the poll interval so a zero/tiny retryDelay can't hammer the network
    // for the whole (possibly minutes-long) onboarding budget.
    final retryDelay = RetryOptions.cap(
      atRequest.retryOptions.retryDelay,
      RetryOptions.defaultRetryOptions.retryDelay,
    );

    // Bound the TOTAL wall-clock of this poll with a single overall deadline.
    // The two paths need opposite budgets: authentication of an EXISTING atSign
    // must fail fast on a dead network (#1923), but ONBOARDING polls for a
    // newly-registered atSign to be provisioned, which can take minutes. So the
    // default depends on the request type. This budget bounds the whole poll and
    // is deliberately NOT clamped to AtNetworkTimeouts.maxAllowed (that cap is
    // for individual network operations); the retry COUNT no longer bounds the
    // loop — the deadline does.
    final overallTimeout = atRequest.retryOptions.overallTimeout ??
        (atRequest is AtOnboardingRequest
            ? AtNetworkTimeouts.defaultOnboardingTimeout
            : AtNetworkTimeouts.effectiveDefault);
    final deadline = DateTime.now().add(overallTimeout);
    int attempt = 0;
    bool validated = false;
    Object? lastError;

    //support mocking
    atServerStatus ??= AtStatusImpl(
      rootUrl: atRequest.rootDomain.rootDomain,
      rootPort: atRequest.rootDomain.rootPort,
    );

    while (DateTime.now().isBefore(deadline)) {
      attempt++;
      try {
        _addProgress(
            'Find',
            '#[$attempt] : looking up ${atRequest.atsign} in atDirectory',
            ProgressEventType.info);

        // Bound each network call by the budget remaining before the deadline,
        // so no single call can overshoot the overall timeout.
        Duration remaining =
            AtNetworkTimeouts.cap(deadline.difference(DateTime.now()));
        var atStatus =
            await atServerStatus!.get(atRequest.atsign).timeout(remaining);

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
                'atSign: ${atRequest.atsign} secondary server is not running. '
                'Cannot perform onboarding. ${atStatus.serverStatus} ${atStatus.atSignStatus}');
          }
          if (atStatus.atSignStatus == AtSignStatus.activated) {
            throw AtException(
                'atSign: ${atRequest.atsign} is already onboarded. Cannot perform onboarding again.');
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
                'atSign: ${atRequest.atsign} secondary server is not running. Cannot perform Authentication.');
          }
          if (atStatus.atSignStatus == AtSignStatus.teapot ||
              atStatus.serverStatus == ServerStatus.teapot) {
            throw AtException(
                'atSign: ${atRequest.atsign} has not been onboarded. Cannot perform Authentication.');
          }
        }

        // AtServer availability probing
        _addProgress(
            'Connect',
            '#[$attempt] : Connecting to ${atRequest.atsign} atServer',
            ProgressEventType.info);

        secondaryAddressFinder ??= CacheableSecondaryAddressFinder(
          atRequest.rootDomain.rootDomain,
          atRequest.rootDomain.rootPort,
        );
        remaining = AtNetworkTimeouts.cap(deadline.difference(DateTime.now()));
        SecondaryAddress secondaryAddress = await secondaryAddressFinder!
            .findSecondary(atRequest.atsign, timeout: remaining);

        remaining = AtNetworkTimeouts.cap(deadline.difference(DateTime.now()));
        await (probeSocket ?? _defaultProbeSocket)(
                secondaryAddress.host, secondaryAddress.port)
            .timeout(remaining);

        _addProgress(
            'Connect',
            '#[$attempt] : Connected to ${atRequest.atsign} atServer',
            ProgressEventType.success);

        validated = true;
        break; // Exit loop if no exception occurs
      } catch (e) {
        lastError = e;
        if (e is SocketException) {
          _logger.warning('Attempt #[$attempt] Probe socket failed: $e');
        } else {
          _logger.severe('Attempt #[$attempt] failed: $e');
        }
        _addProgress('Connect', '#[$attempt] : $e', ProgressEventType.error);
        // Don't sleep past the overall deadline before the next attempt.
        if (!DateTime.now().add(retryDelay).isBefore(deadline)) {
          break;
        }
        await Future.delayed(retryDelay); // Wait before retrying
      }
    }
    if (!validated) {
      // We left the loop because the overall deadline passed (success breaks out
      // above). Surface a timeout with the last error seen.
      throw AtTimeoutException(
          'Timed out after ${overallTimeout.inSeconds}s while reaching '
          '${atRequest.atsign} atServer'
          '${lastError == null ? '' : ' : $lastError'}');
    }
  }
}
