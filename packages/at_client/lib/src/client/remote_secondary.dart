import 'dart:async';
import 'dart:io';

import 'package:at_auth/at_auth.dart'
    show
        AtKeysIo,
        authenticatorFor,
        authenticatorForChops,
        authenticatorForCramSecret,
        authenticatorForPrivateKey;

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/client/secondary_address_finder_source.dart';
import 'package:at_client/src/preference/at_client_config.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_io.dart';
import 'package:at_utils/at_utils.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

/// Contains methods used to execute verbs on remote secondary server of the atSign.
class RemoteSecondary implements Secondary {
  late final AtSignLogger logger;

  late String _atSign;

  late AtClientPreference _preference;

  late AtLookUp atLookUp;

  AtChops? _atChops;

  AtChops? get atChops => _atChops;

  set atChops(AtChops? value) {
    _atChops = value;
    atLookUp.atChops = value;
    _installAuthenticator();
  }

  /// The keystore an authenticator reads, when this client was given one.
  AtKeysIo? _atKeysIo;

  /// The legacy credential, for a client that was given no keystore.
  String? _privateKey;
  String? _cramSecret;

  /// The algorithm the constructor resolved, so an authenticator built from a
  /// bare signer names the same one the lookup was told to use.
  SigningAlgoType? _signingAlgoType;

  /// Hands the lookup an authenticator, so authentication is decided from the
  /// keystore rather than from credentials parked on at_lookup.
  ///
  /// Called from the constructor as well as the [atChops] setter, because the
  /// constructor sets `atLookUp.atChops` directly - hooking only the setter
  /// installs nothing on the path that matters, which was measured: the
  /// injected and ladder authentication counts were unchanged, 57 and 201,
  /// while every suite stayed green.
  ///
  /// Installed beside `atChops`, not instead of it: at_auth's
  /// `EnrollmentApprover` reads that field for enrollment crypto, which is not
  /// authentication.
  void _installAuthenticator() {
    final lookUp = atLookUp;
    // `AtLookUp` does not declare the seam - that interface is frozen because
    // mocks implement it - so any other implementation keeps its behaviour.
    if (lookUp is! AtLookupMuxable) {
      return;
    }

    final io = _atKeysIo;
    if (io != null) {
      lookUp.authenticator = authenticatorFor(
        io,
        _atSign,
        enrollmentId: lookUp.enrollmentId,
        chops: _atChops,
      );
      return;
    }

    // No keystore. The order from here is the ladder's own - atChops, then
    // privateKey - so a client holding both authenticates with the same
    // credential it did before. That precedence is stated rather than fallen
    // into: an earlier version of this method left the private-key branch
    // without a return, so the signer below silently overwrote it. The result
    // was right by accident, which is a bad way to be right.
    final chops = _atChops;
    if (chops != null) {
      lookUp.authenticator = authenticatorForChops(
        _atSign,
        chops,
        enrollmentId: lookUp.enrollmentId,
        signingAlgo: _signingAlgoType ?? SigningAlgoType.rsa2048,
      );
      return;
    }

    // The legacy credential, and precisely the caller the ladder existed for.
    // Without this, deleting the ladder would make a keystore mandatory.
    final privateKey = _privateKey;
    if (privateKey != null) {
      lookUp.authenticator = authenticatorForPrivateKey(
        _atSign,
        privateKey,
        enrollmentId: lookUp.enrollmentId,
      );
      return;
    }

    // Last, matching the ladder's own order: atChops, then privateKey, then
    // cramSecret. Nothing in this tree sets `preference.cramSecret` - every
    // in-tree CRAM goes through onboarding, which builds its own lookup - but
    // the field is public API, so a consumer that sets it kept working through
    // the ladder and must keep working through the seam.
    final cramSecret = _cramSecret;
    if (cramSecret != null) {
      lookUp.authenticator = authenticatorForCramSecret(_atSign, cramSecret);
      return;
    }

    // None of the four: nothing to authenticate with, so nothing is
    // installed. That is a real mode - at_status_impl holds no key material at
    // all, and an OTP enrollment submit routes through auth: false.
  }

  /// [signingAlgoType] overrides the preference's PKAM signing algorithm —
  /// the per-enrollment resolution for a self-retrofit's ML-DSA enrollment,
  /// whose algorithm is a property of the enrollment record, not of the
  /// preference object (one preference can serve clients on two enrollments
  /// of one atSign with different algorithms).
  RemoteSecondary(String atSign, AtClientPreference preference,
      {String? privateKey,
      AtChops? atChops,
      AtLookUp? atLookUp,
      String? enrollmentId,
      SigningAlgoType? signingAlgoType,
      AtKeysIo? atKeysIo}) {
    _atSign = AtUtils.fixAtSign(atSign);
    logger = AtSignLogger('RemoteSecondary ($_atSign)');
    _preference = preference;
    privateKey ??= preference.privateKey;
    SecureSocketConfig secureSocketConfig = SecureSocketConfig()
      ..decryptPackets = preference.decryptPackets
      ..pathToCerts = preference.pathToCerts
      ..tlsKeysSavePath = preference.tlsKeysSavePath;
    _atChops = atChops;
    _atKeysIo = atKeysIo;
    _privateKey = privateKey;
    _cramSecret = preference.cramSecret;
    // privateKey and cramSecret are no longer set ON the lookup: both are
    // credentials, and credentials now travel as an authenticator, which
    // _installAuthenticator supplies below from whichever of the four shapes
    // this client actually holds.
    this.atLookUp = atLookUp ??
        AtLookUp.withSecureSocket(
          atSign: atSign,
          rootDomain: AtRootDomain(preference.rootDomain, preference.rootPort),
          transport: secureSocketTransport(secureSocketConfig),
          authenticator: null,
          secondaryAddressFinder: processSecondaryAddressFinder(),
          clientConfig: _getClientConfig(),
        );
    this.atLookUp.enrollmentId = enrollmentId;
    // The preference is the documented legacy fallback: the caller passes the
    // key-material resolution when the enrollment has typed material.
    final resolvedSigningAlgo =
        // ignore: deprecated_member_use_from_same_package
        signingAlgoType ?? preference.signingAlgoType;
    logger.finer(
        'signingAlgoType: $resolvedSigningAlgo hashingAlgoType: ${preference.hashingAlgoType}');
    _signingAlgoType = resolvedSigningAlgo;
    this.atLookUp.signingAlgoType = resolvedSigningAlgo;
    this.atLookUp.hashingAlgoType = preference.hashingAlgoType;
    this.atLookUp.atChops = atChops;
    _installAuthenticator();
  }

  Map<String, String> _getClientConfig() {
    var clientConfig = <String, String>{};
    clientConfig[AtConstants.version] =
        AtClientConfig.getInstance().atClientVersion;
    clientConfig[AtConstants.clientId] =
        _preference.atClientParticulars.clientId;
    if (_preference.atClientParticulars.appName.isNotNull) {
      clientConfig[AtConstants.appName] =
          _preference.atClientParticulars.appName!;
    }
    if (_preference.atClientParticulars.appVersion.isNotNull) {
      clientConfig[AtConstants.appVersion] =
          _preference.atClientParticulars.appVersion!;
    }
    if (_preference.atClientParticulars.platform.isNotNull) {
      clientConfig[AtConstants.platform] =
          _preference.atClientParticulars.platform!;
    }
    return clientConfig;
  }

  /// Executes the command returned by [VerbBuilder] on a remote
  /// secondary server. Authentication is handled by the injected
  /// `AtLookUp`. [cameFromServer] is accepted for [Secondary] interface
  /// compatibility and ignored — remote secondaries don't have a
  /// client→server sync queue to skip enqueuing into.
  @override
  Future<String> executeVerb(VerbBuilder builder,
      {@Deprecated('Inert: nothing reads it, so passing it suppresses '
          'nothing. Whether a local write is enqueued for '
          'client→server sync is decided by cameFromServer. '
          'Removed in 4.0.')
      sync = false,
      bool cameFromServer = false}) async {
    try {
      String verbResult;
      logger.finer('Command sent to server: ${builder.buildCommand()}');
      verbResult = (await atLookUp.executeVerb(builder))!;
      logger.finer('Response from server: $verbResult');
      return verbResult;
    } on AtException catch (e) {
      throw e
        ..stack(AtChainedException(_getIntent(builder),
            ExceptionScenario.remoteVerbExecutionFailed, e.message));
    } on AtLookUpException catch (e) {
      var exception = AtExceptionUtils.get(e.errorCode, e.errorMessage);
      throw exception
        ..stack(AtChainedException(_getIntent(builder),
            ExceptionScenario.remoteVerbExecutionFailed, exception.message));
    }
  }

  Future<String> executeAndParse(VerbBuilder builder,
      {@Deprecated('Inert: nothing reads it, so passing it suppresses '
          'nothing. Whether a local write is enqueued for '
          'client→server sync is decided by cameFromServer. '
          'Removed in 4.0.')
      sync = false}) async {
    // ignore: prefer_typing_uninitialized_variables
    var verbResult;
    try {
      verbResult = await executeVerb(builder);
      verbResult = verbResult.replaceFirst(RegExp('^data:'), '');
    } on AtException catch (e) {
      throw e
        ..stack(AtChainedException(Intent.fetchData,
            ExceptionScenario.remoteVerbExecutionFailed, e.message));
    }
    return verbResult;
  }

  Future<String?> executeCommand(String atCommand, {bool auth = false}) async {
    if (atCommand.length > _preference.maxDataSize) {
      throw BufferOverFlowException(
          'The length of value exceeds the maximum allowed length. Maximum buffer size is ${_preference.maxDataSize} bytes. Found ${atCommand.length} bytes');
    }
    try {
      String? verbResult;
      verbResult = await atLookUp.executeCommand(atCommand, auth: auth);
      return verbResult;
    } on AtException catch (e) {
      e.stack(AtChainedException(Intent.fetchData,
          ExceptionScenario.remoteVerbExecutionFailed, e.message));
      rethrow;
    } on AtLookUpException catch (e) {
      var exception = AtExceptionUtils.get(e.errorCode, e.errorMessage);
      throw exception
        ..stack(AtChainedException(Intent.fetchData,
            ExceptionScenario.remoteVerbExecutionFailed, exception.message));
    }
  }

  void addStreamData(List<int> data) {
    atLookUp.connection!.getSocket().add(data);
  }

  /// Generates digest using from verb response and [secret] and performs a CRAM authentication to
  /// secondary server
  Future<bool> authenticateCram(String? secret) async {
    if (secret == null) {
      throw UnAuthenticatedException('Cram secret cannot be null');
    }
    var authResult = await atLookUp.cramAuthenticate(secret);
    return authResult;
  }

  /// Executes sync verb on the remote server. Return commit entries greater than [lastSyncedId].
  Future<String?> sync(int lastSyncedId, {String? regex}) async {
    var syncVerbBuilder = SyncVerbBuilder()
      ..commitId = lastSyncedId
      ..regex = regex
      ..limit = _preference.syncPageLimit;

    var atCommand = syncVerbBuilder.buildCommand();
    return await atLookUp.executeCommand(atCommand, auth: true);
  }

  Future<String?> findSecondaryUrl() async {
    var secondaryAddress =
        await processSecondaryAddressFinder()!.findSecondary(_atSign);
    return secondaryAddress.toString();
  }

  @Deprecated('This method is unused and will be removed in next major release')
  Future<bool> isAvailable() async {
    try {
      String? secondaryUrl = await findSecondaryUrl();

      var secondaryInfo = AtClientUtil.getSecondaryInfo(secondaryUrl);
      var host = secondaryInfo[0];
      var port = secondaryInfo[1];
      var internetAddress = await InternetAddress.lookup(host);
      // TODO: getting first ip for now. explore best solution
      var addressCheckOptions = AddressCheckOptions(
          address: internetAddress[0], port: int.parse(port));
      var addressCheckResult = await InternetConnectionChecker()
          .isHostReachable(addressCheckOptions);
      return addressCheckResult.isSuccess;
    } on Exception catch (e) {
      logger.severe(
          'Secondary server unavailable due to Exception: ${e.toString()}');
    } on Error catch (e) {
      logger
          .severe('Secondary server unavailable due to Error: ${e.toString()}');
    }
    return false;
  }

  Intent _getIntent(VerbBuilder builder) {
    if (builder is NotifyVerbBuilder) {
      return Intent.notifyData;
    }
    if (builder is UpdateVerbBuilder) {
      return Intent.shareData;
    }
    if (builder is SyncVerbBuilder) {
      return Intent.syncData;
    }
    return Intent.fetchData;
  }

  Future<void> closeConnection() async {
    await atLookUp.close();
  }
}
