import 'dart:async';
import 'package:at_client/src/lifecycle/lookups.dart';

import 'package:at_auth/at_auth.dart'
    show
        AtKeysIo,
        authenticatorFor,
        authenticatorForCramSecret,
        authenticatorForPrivateKey;

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/client/secondary_address_finder_source.dart';
import 'package:at_client/src/lifecycle/at_connection.dart';
import 'package:at_client/src/preference/at_client_config.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart';

/// Contains methods used to execute verbs on remote secondary server of the atSign.
class RemoteSecondary implements Secondary {
  late final AtSignLogger logger;

  late String _atSign;

  late AtClientPreference _preference;

  late AtLookUp atLookUp;

  /// The atDirectory lookup this connection resolves its atServer with, or
  /// null to read the process-wide one per lookup.
  SecondaryAddressFinder? _secondaryAddressFinder;

  /// The keystore an authenticator reads, when this client was given one.
  AtKeysIo? _atKeysIo;

  /// The legacy credential, for a client that was given no keystore.
  String? _privateKey;
  String? _cramSecret;

  /// The enrollment the next authenticator built by [_installAuthenticator]
  /// should declare.
  String? _enrollmentId;

  /// Where this connection's outcomes are reported, when the client gave it
  /// one: every verb that comes back says online, every one that cannot get
  /// out or is refused says which.
  AtConnection? _connection;

  void _reportSuccess() => _connection?.report(AtConnectionState.online());

  void _reportFailure(Object error) {
    final state = classifyConnectionFailure(error);
    if (state != null) _connection?.report(state);
  }

  /// Hands the lookup the authenticator [clientAuthenticator] builds from
  /// this client's credentials, leaving it as it was when they hold none.
  void _installAuthenticator() {
    final authenticator = clientAuthenticator(_atSign,
        atKeysIo: _atKeysIo,
        privateKey: _privateKey,
        cramSecret: _cramSecret,
        enrollmentId: _enrollmentId,
        clientConfig: _getClientConfig());
    if (authenticator != null) atLookUp.authenticator = authenticator;
  }

  /// [connection] is the client's connection state, which every verb here
  /// then reports into; a secondary built without one reports nowhere.
  ///
  /// [secondaryAddressFinder] resolves the atServer address; with none, the
  /// process-wide finder is read per lookup.
  RemoteSecondary(String atSign, AtClientPreference preference,
      {String? privateKey,
      AtLookUp? atLookUp,
      String? enrollmentId,
      @Deprecated('Has no effect: the keys name the algorithm they sign with. '
          'Removed in 5.0.0.')
      SigningAlgoType? signingAlgoType,
      AtKeysIo? atKeysIo,
      AtConnection? connection,
      SecondaryAddressFinder? secondaryAddressFinder,
      AtLookUpFactory? lookUps}) {
    _atSign = AtUtils.fixAtSign(atSign);
    _secondaryAddressFinder = secondaryAddressFinder;
    logger = AtSignLogger('RemoteSecondary ($_atSign)');
    _preference = preference;
    _connection = connection;
    privateKey ??= preference.privateKey;
    _atKeysIo = atKeysIo;
    _privateKey = privateKey;
    _cramSecret = preference.cramSecret;
    _enrollmentId = enrollmentId;
    // Credentials travel as an authenticator, which _installAuthenticator
    // supplies below from whichever of the four shapes this client holds -
    // none of them are set on the lookup itself.
    this.atLookUp = atLookUp ??
        (lookUps ?? defaultLookUps(preference))(
          atSign: atSign,
          rootDomain: AtRootDomain(preference.rootDomain, preference.rootPort),
          authenticator: null,
          secondaryAddressFinder:
              secondaryAddressFinder ?? processSecondaryAddressFinder(),
          clientConfig: _getClientConfig(),
        );
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
      {bool cameFromServer = false}) async {
    _throwIfStopped();
    try {
      String verbResult;
      logger.finer('Command sent to server: ${builder.buildCommand()}');
      verbResult = (await atLookUp.executeVerb(builder))!;
      logger.finer('Response from server: $verbResult');
      _reportSuccess();
      return verbResult;
    } on AtException catch (e) {
      _reportFailure(e);
      throw e
        ..stack(AtChainedException(_getIntent(builder),
            ExceptionScenario.remoteVerbExecutionFailed, e.message));
    } on AtLookUpException catch (e) {
      _reportFailure(e);
      var exception = AtExceptionUtils.get(e.errorCode, e.errorMessage);
      throw exception
        ..stack(AtChainedException(_getIntent(builder),
            ExceptionScenario.remoteVerbExecutionFailed, exception.message));
    }
  }

  Future<String> executeAndParse(VerbBuilder builder) async {
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
    _throwIfStopped();
    if (atCommand.length > _preference.maxDataSize) {
      throw BufferOverFlowException(
          'The length of value exceeds the maximum allowed length. Maximum buffer size is ${_preference.maxDataSize} bytes. Found ${atCommand.length} bytes');
    }
    try {
      String? verbResult;
      verbResult = await atLookUp.executeCommand(atCommand, auth: auth);
      // NOTE: only an authenticated command proves the credentials; an
      // unauthenticated one that comes back says the atServer is reachable,
      // which is not the same thing, and is reported by the next one.
      if (auth) _reportSuccess();
      return verbResult;
    } on AtException catch (e) {
      _reportFailure(e);
      e.stack(AtChainedException(Intent.fetchData,
          ExceptionScenario.remoteVerbExecutionFailed, e.message));
      rethrow;
    } on AtLookUpException catch (e) {
      _reportFailure(e);
      var exception = AtExceptionUtils.get(e.errorCode, e.errorMessage);
      throw exception
        ..stack(AtChainedException(Intent.fetchData,
            ExceptionScenario.remoteVerbExecutionFailed, exception.message));
    }
  }

  void addStreamData(List<int> data) {
    atLookUp.connection!.add(data);
  }

  /// Generates digest using from verb response and [secret] and performs a CRAM authentication to
  /// secondary server
  Future<bool> authenticateCram(String? secret) async {
    _throwIfStopped();
    if (secret == null) {
      throw UnAuthenticatedException('Cram secret cannot be null');
    }
    atLookUp.authenticator = authenticatorForCramSecret(_atSign, secret);
    return atLookUp.pkamAuthenticate();
  }

  /// Executes sync verb on the remote server. Return commit entries greater than [lastSyncedId].
  Future<String?> sync(int lastSyncedId, {String? regex}) async {
    _throwIfStopped();
    var syncVerbBuilder = SyncVerbBuilder()
      ..commitId = lastSyncedId
      ..regex = regex
      ..limit = _preference.syncPageLimit;

    var atCommand = syncVerbBuilder.buildCommand();
    try {
      final result = await atLookUp.executeCommand(atCommand, auth: true);
      _reportSuccess();
      return result;
    } catch (e) {
      _reportFailure(e);
      rethrow;
    }
  }

  Future<String?> findSecondaryUrl() async {
    var secondaryAddress =
        await (_secondaryAddressFinder ?? processSecondaryAddressFinder()!)
            .findSecondary(_atSign);
    return secondaryAddress.toString();
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

  /// Closes the connection and ends this remote secondary for good: every
  /// later call through it fails with [StoppedException]. A connection meant
  /// to be re-established uses [AtLookupMuxable.dropConnection] instead.
  Future<void> closeConnection() async {
    _stopped = true;
    await atLookUp.stop();
  }

  bool _stopped = false;

  void _throwIfStopped() {
    if (_stopped) {
      throw StoppedException('the connection for $_atSign has been stopped');
    }
  }
}

/// The authenticator a client's connections share, built from the first of
/// its credentials it holds: a keystore [atKeysIo], a bare PKAM [privateKey],
/// a CRAM [cramSecret]. Null when it holds none, which is a real mode: an
/// OTP enrollment's submit runs unauthenticated.
AtAuthenticator? clientAuthenticator(
  String atSign, {
  AtKeysIo? atKeysIo,
  String? privateKey,
  String? cramSecret,
  String? enrollmentId,
  Map<String, dynamic> clientConfig = const {},
}) {
  if (atKeysIo != null) {
    return authenticatorFor(atKeysIo, atSign,
        enrollmentId: enrollmentId, clientConfig: clientConfig);
  }
  if (privateKey != null) {
    return authenticatorForPrivateKey(atSign, privateKey,
        enrollmentId: enrollmentId, clientConfig: clientConfig);
  }
  if (cramSecret != null) {
    return authenticatorForCramSecret(atSign, cramSecret,
        clientConfig: clientConfig);
  }
  return null;
}
