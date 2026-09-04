import 'dart:async';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/preference/at_client_config.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
// at_lookup_io.dart re-exports at_lookup.dart and adds the socket transport;
// naming it is what selects the native transport, which is the default this
// class still supplies.
import 'package:at_lookup/at_lookup_io.dart';
import 'package:at_utils/at_utils.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

/// Contains methods used to execute verbs on remote secondary server of the atSign.
class RemoteSecondary implements Secondary {
  late final AtSignLogger logger;

  late String _atSign;

  late AtClientPreference _preference;

  late AtLookUp atLookUp;

  /// Not forwarded to [atLookUp]: the [AtAuthenticator] installed at
  /// construction reads this field on every connect, so a change here reaches
  /// the next authentication without the lookup ever holding key material of
  /// its own.
  AtChops? atChops;

  /// The bare PKAM private key, when that is the only credential this client
  /// has. Second rung of [_authenticate]'s ladder.
  late final String? _privateKey;

  late final String? _enrollmentId;

  /// [transport] says how connections to the atServer are made — at_lookup's
  /// three socket factories plus the [SecureSocketConfig] they use, as one
  /// value. Omitting it builds the TLS-over-TCP transport from [preference],
  /// which is what every caller that does not inject gets.
  ///
  /// Supplying it replaces that configuration wholesale, [preference]'s
  /// `decryptPackets` / `pathToCerts` / `tlsKeysSavePath` included: a
  /// transport carries its own settings, because TLS certificates and a
  /// keylog path mean nothing to a transport that is not TLS over TCP.
  ///
  /// The default names an implementation, which
  /// `docs/projects/wasm/design.md` §1 rule 2 forbids for exactly the reason
  /// it gives — it re-imports the native graph regardless of what the caller
  /// injects. Removing it has no additive form, so it waits for at_client
  /// 4.0.0 and `at_client_io.dart`.
  ///
  /// Ignored when [atLookUp] is supplied: that branch adopts the caller's
  /// lookup rather than building one, so there is nothing to configure.
  RemoteSecondary(String atSign, AtClientPreference preference,
      {String? privateKey,
      this.atChops,
      AtLookUp? atLookUp,
      String? enrollmentId,
      AtLookupTransport? transport}) {
    _atSign = AtUtils.fixAtSign(atSign);
    logger = AtSignLogger('RemoteSecondary ($_atSign)');
    _preference = preference;
    _privateKey = privateKey ?? preference.privateKey;
    _enrollmentId = enrollmentId;
    logger.finer(
        'signingAlgoType: ${preference.signingAlgoType} hashingAlgoType: ${preference.hashingAlgoType}');
    this.atLookUp = atLookUp ??
        AtLookUp.withSecureSocket(
          atSign: _atSign,
          rootDomain: AtRootDomain(preference.rootDomain, preference.rootPort),
          transport: transport ??
              secureSocketTransport(SecureSocketConfig()
                ..decryptPackets = preference.decryptPackets
                ..pathToCerts = preference.pathToCerts
                ..tlsKeysSavePath = preference.tlsKeysSavePath),
          clientConfig: _getClientConfig(),
          secondaryAddressFinder:
              AtClientManager.getInstance().secondaryAddressFinder,
          authenticator: _authenticate,
        );
  }

  /// Authenticates one connection, choosing the credential afresh each time.
  ///
  /// A method rather than a closure built in the constructor, because
  /// [atChops] is writable — `AtClient.atChops` forwards to it — and at_lookup
  /// calls this once per connection that needs authenticating. A credential
  /// captured at construction would be the wrong answer for the second
  /// connection.
  ///
  /// The order is at_lookup's own credential ladder — atChops, then a bare
  /// private key, then a CRAM secret — which this replaces rather than
  /// changes. at_auth owns the three builders; at_lookup cannot name key
  /// material.
  Future<bool> _authenticate(AtCommandExecutor executor) {
    final chops = atChops;
    if (chops != null) {
      return authenticatorForChops(
        _atSign,
        chops,
        enrollmentId: _enrollmentId,
        signingAlgo: _preference.signingAlgoType,
        hashingAlgo: _preference.hashingAlgoType,
        clientConfig: _getClientConfig(),
      )(executor);
    }
    final privateKey = _privateKey;
    if (privateKey != null) {
      return authenticatorForPrivateKey(
        _atSign,
        privateKey,
        enrollmentId: _enrollmentId,
        clientConfig: _getClientConfig(),
      )(executor);
    }
    final cramSecret = _preference.cramSecret;
    if (cramSecret != null) {
      return authenticatorForCramSecret(
        _atSign,
        cramSecret,
        clientConfig: _getClientConfig(),
      )(executor);
    }
    throw UnAuthenticatedException(
        'Unable to perform atLookup auth. atChops object is not set');
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
  /// `AtLookUp`. [sync] is accepted for [Secondary] interface
  /// compatibility but is ignored. [cameFromServer] is also accepted
  /// for interface compatibility and ignored — remote secondaries
  /// don't have a client→server sync queue to skip enqueuing into.
  @override
  Future<String> executeVerb(VerbBuilder builder,
      {sync = false, bool cameFromServer = false}) async {
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

  Future<String> executeAndParse(VerbBuilder builder, {sync = false}) async {
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
    var secondaryAddress = await AtClientManager.getInstance()
        .secondaryAddressFinder!
        .findSecondary(_atSign);
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
