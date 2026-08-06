import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:at_auth/src/at_auth.dart';
import 'package:at_auth/src/auth/apkam_signing_scheme.dart';
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

import 'auth/retry_options.dart';

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

  @override
  final ApkamSigningScheme signing;

  /// Builds the [AtEnrollment] for a connection. Deferred because enrollment
  /// needs a connection, and the connection needs the keys.
  final AtEnrollment Function(AtLookUp) enrollmentFactory;

  @override
  RetryOptions retryOptions;

  @visibleForTesting
  AtServerStatus? atServerStatus;

  @visibleForTesting
  SecondaryAddressFinder? secondaryAddressFinder;

  @visibleForTesting
  Future<void> Function(String host, int port)? probeSocket;

  /// Builds every connection this instance authenticates on. at_lookup binds its
  /// PKAM key at construction, so a connection cannot exist until the keys have
  /// been read or minted — which is why this is a factory and not a connection.
  final AtLookUpFactory _lookUpFactory;

  AtLookUp? _atLookUp;

  @override
  AtLookUp? get atLookUp => _atLookUp;

  AtAuthImpl({
    required this.retryOptions,
    this.signing = ApkamSigningScheme.legacy,
    this.cramAuthenticator,
    this.pkamAuthenticator,
    this.atServerStatus,
    AtEnrollment Function(AtLookUp)? enrollmentFactory,
    AtLookUpFactory? atLookUpFactory,
  })  : enrollmentFactory = enrollmentFactory ?? AtEnrollment.create,
        _lookUpFactory = atLookUpFactory ?? signing.lookUpFactory;

  /// The single construction point: every connection an operation here runs over
  /// comes from here, so a caller substituting [_lookUpFactory] substitutes all
  /// of them.
  AtLookUp _lookUpFor(
    Atsign atsign,
    AtRootDomain rootDomain,
    AtKeys? keys,
    String? enrollmentId,
  ) =>
      _lookUpFactory(atsign, rootDomain, keys, enrollmentId: enrollmentId);

  /// Authenticate using PKAM.
  ///
  /// The keys always come from [atKeysIo] — an [AtKeysIo] implementation over a
  /// file, keychain, or memory. To authenticate with keys you already hold, put
  /// them in an [InMemoryAtKeysIo].
  ///
  /// Optionally, [enrollmentId] selects the enrollment to authenticate as; when
  /// it is null the enrollmentId stored in the keys is used.
  ///
  /// Completing normally means authenticated, and [atLookUp] is the connection
  /// it happened on. On failure this throws [AtAuthenticationException] and
  /// closes any connection it opened.
  @override
  Future<void> authenticate(
    Atsign atsign,
    AtRootDomain rootDomain,
    AtKeysIo atKeysIo, {
    String? enrollmentId,
  }) async {
    _progress(
      "authentication",
      "Authenticating atSign: $atsign",
      ProgressEventType.info,
    );
    await validateAtServer(atsign, rootDomain);
    AtKeys atKeys;
    try {
      atKeys = await atKeysIo.read(atsign);
    } on AtKeyException catch (e, s) {
      _progress(
        "authentication",
        "Unable to read keys for atSign: $atsign",
        ProgressEventType.error,
        error: e,
        stackTrace: s,
      );
      Error.throwWithStackTrace(
        AtAuthenticationException(
          'Unable to read keys for atSign: $atsign | Cause: ${e.message}',
        ),
        s,
      );
    }
    // set enrollmentId to whats in the AtKeys if it exists
    // so enrollmentId can still be nullable here.
    enrollmentId ??= atKeys.enrollmentId;

    _logger.finer('Authenticating atSign: $atsign using PKAM '
        '(enrollmentId: $enrollmentId)');
    pkamAuthenticator ??= PkamAuthenticator();
    // The signing key is bound into the connection here — this is the only
    // place the keys just read reach the PKAM handshake.
    final lookUp = _lookUpFor(atsign, rootDomain, atKeys, enrollmentId);
    try {
      // Throws UnAuthenticatedException on failure; reaching past this call
      // means PKAM succeeded.
      await pkamAuthenticator!.authenticate(
        atsign,
        lookUp,
        enrollmentId: enrollmentId,
      );
      _atLookUp = lookUp;

      _progress(
        "authentication",
        "PKAM authentication successful for atSign: $atsign",
        ProgressEventType.success,
      );
    } catch (e, s) {
      _progress(
        "authentication",
        "PKAM authentication failed for atSign: $atsign",
        ProgressEventType.error,
        error: e,
        stackTrace: s,
      );
      // A throw here abandons the connection we opened — close it before the
      // error propagates so a failed authenticate doesn't leak the AtLookup.
      _atLookUp = null;
      await _closeQuietly(lookUp);
      Error.throwWithStackTrace(
        AtAuthenticationException('Unable to authenticate | Cause: $e'),
        s,
      );
    }
  }

  /// Best-effort teardown of a connection on a failure path, so a throw doesn't
  /// leak the AtLookup we opened.
  Future<void> _closeQuietly(AtLookUp? lookUp) async {
    if (lookUp == null) {
      return;
    }
    try {
      await lookUp.close();
    } catch (_) {
      // cleanup is best-effort
    }
  }

  /// Onboard a new atSign using CRAM.
  ///
  /// Mints a fresh keyset, enrolls it over the CRAM connection,
  /// PKAM-authenticates on a second connection built from the new key, and
  /// persists the keys through [atKeysIo].
  ///
  /// Completing normally means activated, and [atLookUp] is the
  /// PKAM-authenticated connection. Failure throws.
  @override
  Future<void> onboard(
    Atsign atsign,
    AtRootDomain rootDomain,
    AtKeysIo atKeysIo,
    String cramSecret, {
    bool mintLegacy = true,
    bool autoCompleteActivation = true,
    String appName = FirstEnrollmentRequest.defaultAppName,
    String deviceName = FirstEnrollmentRequest.defaultDeviceName,
  }) async {
    _progress(
      "onboarding",
      "Onboarding atSign: $atsign",
      ProgressEventType.info,
    );

    // Activation needs two connections. at_lookup binds its PKAM key at
    // construction, so the connection that CRAM-authenticates cannot later sign
    // with a key that did not exist when it was built.
    AtLookUp? cramLookUp;
    AtLookUp? pkamLookUp;

    //1. cram auth
    try {
      await validateAtServer(atsign, rootDomain, onboarding: true);
      cramAuthenticator ??= CramAuthenticator();
      cramLookUp = _lookUpFor(atsign, rootDomain, null, null);
      try {
        // Throws UnAuthenticatedException on failure.
        await cramAuthenticator!.authenticate(
          atsign,
          cramSecret,
          cramLookUp,
        );
      } on UnAuthenticatedException catch (e, s) {
        _progress(
          "onboarding",
          "CRAM authentication failed for atSign: $atsign",
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
        "CRAM authentication successful for atSign: $atsign",
        ProgressEventType.success,
      );

      //2. generate key pairs
      AtKeys atKeys = await AtKeys.generate(atsign, mintLegacy: mintLegacy);

      //3. send onboarding enrollment over the CRAM connection, which is what
      // makes the atServer auto-approve it
      String? enrollmentIdFromServer;
      // server will update the apkam public key during enrollment.
      // So don't have to manually update apkam public key in this scenario.
      enrollmentIdFromServer = await _sendOnboardingEnrollment(
        atsign,
        rootDomain,
        atKeys,
        cramLookUp,
        appName,
        deviceName,
      );
      atKeys.enrollmentId = enrollmentIdFromServer;

      // The CRAM connection has done its job and cannot sign with the new key.
      await _closeQuietly(cramLookUp);
      cramLookUp = null;

      //4. Do pkam auth on a connection built from the key we just minted
      pkamAuthenticator ??= PkamAuthenticator();
      pkamLookUp =
          _lookUpFor(atsign, rootDomain, atKeys, enrollmentIdFromServer);
      try {
        // Throws UnAuthenticatedException on failure.
        await pkamAuthenticator!.authenticate(atsign, pkamLookUp,
            enrollmentId: enrollmentIdFromServer);
        _atLookUp = pkamLookUp;
        _progress(
            "onboarding",
            "PKAM authentication successful for atSign: $atsign",
            ProgressEventType.success);
      } on UnAuthenticatedException catch (e, s) {
        _progress(
            "onboarding",
            "PKAM authentication failed for atSign: $atsign",
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
        await atKeysIo.write(
          atsign,
          atKeys,
        );
        _progress(
          "onboarding",
          "Successfully stored keys for atSign: $atsign",
          ProgressEventType.success,
        );
      } catch (e, s) {
        _progress(
          "onboarding",
          "Unable to store keys for atSign: $atsign",
          ProgressEventType.error,
          error: e,
          stackTrace: s,
        );
        Error.throwWithStackTrace(
          AtAuthenticationException(
            'Unable to store keys for atSign: $atsign | Cause: ${e.toString()}',
          ),
          s,
        );
      }

      //5. If so specified (default behaviour) then
      // - set the public encryption key
      // - delete the cram secret from the keystore
      if (autoCompleteActivation) {
        await completeActivation(atsign, rootDomain, atKeysIo);
      }

      _progress("onboarding", "Onboarding successful for atSign: $atsign",
          ProgressEventType.success);
    } catch (e) {
      // Any throw above abandons the AtLookups we opened (the inner catches
      // rethrow into here) — close them before the error propagates so a failed
      // onboard doesn't leak a connection.
      _atLookUp = null;
      await _closeQuietly(cramLookUp);
      await _closeQuietly(pkamLookUp);
      rethrow;
    }
  }

  @override
  Future<void> completeActivation(
    Atsign atsign,
    AtRootDomain rootDomain,
    AtKeysIo atKeysIo,
  ) async {
    // Reuse the connection onboard/authenticate already established; called on
    // its own, this has to authenticate first.
    if (_atLookUp == null) {
      await authenticate(atsign, rootDomain, atKeysIo);
    }
    final lookUp = _atLookUp!;

    AtKeys atKeys = await atKeysIo.read(atsign);
    final encryptionPublicKey = atKeys.defaultEncryptionPublicKey;
    UpdateVerbBuilder updateBuilder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'publickey'
        ..sharedBy = atsign
        ..metadata = (Metadata()
          ..isPublic = true
          ..ttr = -1))
      ..value = encryptionPublicKey;
    String? encryptKeyUpdateResult = await lookUp.executeVerb(updateBuilder);
    _logger.info('Encryption public key update result $encryptKeyUpdateResult');

    DeleteVerbBuilder deleteBuilder = DeleteVerbBuilder()
      ..atKey = (AtKey()..key = AtConstants.atCramSecret);
    String? deleteResponse = await lookUp.executeVerb(deleteBuilder);
    _logger.info('Cram secret delete response : $deleteResponse');
  }

  Future<String> _sendOnboardingEnrollment(
    Atsign atsign,
    AtRootDomain rootDomain,
    AtKeys atKeys,
    AtLookUp cramLookUp,
    String appName,
    String deviceName,
  ) async {
    _logger.finer('apkamPublicKey: ${atKeys.apkamPublicKey}');

    FirstEnrollmentRequest request = FirstEnrollmentRequest(
      atsign: atsign,
      rootDomain: rootDomain,
      appName: appName,
      deviceName: deviceName,
      apkamPublicKey: atKeys.apkamPublicKey!.toString(),
    );

    AtEnrollmentResponse? atEnrollmentResponse;
    try {
      atEnrollmentResponse =
          await enrollmentFactory(cramLookUp).enroll(request);
    } on AtEnrollmentException catch (e, s) {
      _progress("onboarding", "Enrollment failed for atSign: ${request.atsign}",
          ProgressEventType.error,
          error: e, stackTrace: s);
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
  Future<void> validateAtServer(Atsign atsign, AtRootDomain rootDomain,
      {bool onboarding = false}) async {
    // Floor the poll interval so a zero/tiny retryDelay can't hammer the network
    // for the whole (possibly minutes-long) onboarding budget.
    final retryDelay = RetryOptions.cap(
      retryOptions.retryDelay,
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
    final overallTimeout = retryOptions.overallTimeout ??
        (onboarding
            ? AtNetworkTimeouts.defaultOnboardingTimeout
            : AtNetworkTimeouts.effectiveDefault);
    final deadline = DateTime.now().add(overallTimeout);
    int attempt = 0;
    bool validated = false;
    Object? lastError;

    //support mocking
    atServerStatus ??= AtStatusImpl(
      rootUrl: rootDomain.rootDomain,
      rootPort: rootDomain.rootPort,
    );

    while (DateTime.now().isBefore(deadline)) {
      attempt++;
      try {
        _addProgress('Find', '#[$attempt] : looking up $atsign in atDirectory',
            ProgressEventType.info);

        // Bound each network call by the budget remaining before the deadline,
        // so no single call can overshoot the overall timeout.
        Duration remaining =
            AtNetworkTimeouts.cap(deadline.difference(DateTime.now()));
        var atStatus = await atServerStatus!.get(atsign).timeout(remaining);

        // 3 Checks for onboarding:
        //   1. Root server should be found
        //   2. Secondary server should be running
        //   3. atSign should not be activated already
        if (onboarding) {
          if (atStatus.rootStatus != RootStatus.found) {
            throw AtException(
                'Could not find root server: ${rootDomain.rootDomain}');
          }
          if (atStatus.serverStatus == ServerStatus.error ||
              atStatus.atSignStatus == AtSignStatus.notFound) {
            throw AtException(
                'atSign: $atsign secondary server is not running. '
                'Cannot perform onboarding. ${atStatus.serverStatus} ${atStatus.atSignStatus}');
          }
          if (atStatus.atSignStatus == AtSignStatus.activated) {
            throw AtException(
                'atSign: $atsign is already onboarded. Cannot perform onboarding again.');
          }
        }

        // 3 Checks for authentication:
        //   1. Root server should be found
        //   2. Secondary server should be running
        //   3. atSign should be activated already
        else {
          if (atStatus.rootStatus == RootStatus.notFound ||
              atStatus.rootStatus == RootStatus.error) {
            throw AtException(
                'Could not find root server: ${rootDomain.rootDomain}');
          }
          if (atStatus.serverStatus == ServerStatus.stopped ||
              atStatus.serverStatus == ServerStatus.error ||
              atStatus.serverStatus == ServerStatus.unavailable) {
            throw AtException(
                'atSign: $atsign secondary server is not running. Cannot perform Authentication.');
          }
          if (atStatus.atSignStatus == AtSignStatus.teapot ||
              atStatus.serverStatus == ServerStatus.teapot) {
            throw AtException(
                'atSign: $atsign has not been onboarded. Cannot perform Authentication.');
          }
        }

        // AtServer availability probing
        _addProgress('Connect', '#[$attempt] : Connecting to $atsign atServer',
            ProgressEventType.info);

        secondaryAddressFinder ??= CacheableSecondaryAddressFinder(
          rootDomain.rootDomain,
          rootDomain.rootPort,
        );
        remaining = AtNetworkTimeouts.cap(deadline.difference(DateTime.now()));
        SecondaryAddress secondaryAddress = await secondaryAddressFinder!
            .findSecondary(atsign, timeout: remaining);

        remaining = AtNetworkTimeouts.cap(deadline.difference(DateTime.now()));
        await (probeSocket ?? _defaultProbeSocket)(
                secondaryAddress.host, secondaryAddress.port)
            .timeout(remaining);

        _addProgress('Connect', '#[$attempt] : Connected to $atsign atServer',
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
          '$atsign atServer'
          '${lastError == null ? '' : ' : $lastError'}');
    }
  }
}
