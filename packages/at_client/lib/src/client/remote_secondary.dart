import 'dart:async';
import 'dart:io';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/preference/at_client_config.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_client/src/util/logger_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:meta/meta.dart';

/// Contains methods used to execute verbs on remote secondary server of the atSign.
class RemoteSecondary implements Secondary {
  late final AtSignLogger logger;

  late String _atSign;

  late AtClientPreference _preference;

  late AtLookupImpl atLookUp;

  final AtChops? atChops;

  RemoteSecondary(String atSign, AtClientPreference preference,
      {String? privateKey, this.atChops, String? enrollmentId}) {
    _atSign = AtUtils.fixAtSign(atSign);
    logger = AtSignLogger('RemoteSecondary ($_atSign)');
    _preference = preference;
    privateKey ??= preference.privateKey;
    SecureSocketConfig secureSocketConfig = SecureSocketConfig();
    secureSocketConfig.decryptPackets = preference.decryptPackets;
    secureSocketConfig.pathToCerts = preference.pathToCerts;
    secureSocketConfig.tlsKeysSavePath = preference.tlsKeysSavePath;
    atLookUp = AtLookupImpl(atSign, preference.rootDomain, preference.rootPort,
        privateKey: privateKey,
        cramSecret: preference.cramSecret,
        secondaryAddressFinder:
            AtClientManager.getInstance().secondaryAddressFinder,
        secureSocketConfig: secureSocketConfig,
        clientConfig: _getClientConfig());
    atLookUp.enrollmentId = enrollmentId;
    logger.finer(
        'signingAlgoType: ${preference.signingAlgoType} hashingAlgoType: ${preference.hashingAlgoType}');
    atLookUp.signingAlgoType = preference.signingAlgoType;
    atLookUp.hashingAlgoType = preference.hashingAlgoType;
    atLookUp.atChops = atChops;
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

  @experimental
  AtTelemetryService? telemetry;

  /// Executes the command returned by [VerbBuilder] build command on a remote secondary server.
  /// Optionally [privateKey] is passed for verb builders which require authentication.

  @override
  Future<String> executeVerb(VerbBuilder builder, {sync = false}) async {
    try {
      String verbResult;
      logger.finer(logger.getLogMessageWithClientParticulars(
          _preference.atClientParticulars,
          'Command sent to server: ${builder.buildCommand()}'));
      verbResult = await atLookUp.executeVerb(builder);
      logger.finer(logger.getLogMessageWithClientParticulars(
          _preference.atClientParticulars,
          'Response from server: $verbResult'));
      return verbResult;
    } on AtException catch (e) {
      throw e
        ..stack(AtChainedException(_getIntent(builder),
            ExceptionScenario.remoteVerbExecutionFailed, e.message));
    } on AtLookUpException catch (e) {
      var exception = AtExceptionUtils.get(e.errorCode!, e.errorMessage!);
      throw exception
        ..stack(AtChainedException(_getIntent(builder),
            ExceptionScenario.remoteVerbExecutionFailed, exception.message));
    }
  }

  Future<String> executeAndParse(VerbBuilder builder, {sync = false}) async {
    // ignore: prefer_typing_uninitialized_variables
    var verbResult;
    try {
      logger.finer(logger.getLogMessageWithClientParticulars(
          _preference.atClientParticulars,
          'Command sent to server: ${builder.buildCommand()}'));
      verbResult = await executeVerb(builder);
      verbResult = verbResult.replaceFirst('data:', '');
      logger.finer(logger.getLogMessageWithClientParticulars(
          _preference.atClientParticulars,
          'Response from server: $verbResult'));
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
      var exception = AtExceptionUtils.get(e.errorCode!, e.errorMessage!);
      throw exception
        ..stack(AtChainedException(Intent.fetchData,
            ExceptionScenario.remoteVerbExecutionFailed, exception.message));
    }
  }

  void addStreamData(List<int> data) {
    atLookUp.connection!.getSocket().add(data);
  }

  /// Generates digest using from verb response and [privateKey] and performs a PKAM authentication to
  /// secondary server. This method is executed for all verbs that requires authentication.
  Future<bool> authenticate(var privateKey) async {
    var authResult = await atLookUp.authenticate(privateKey);
    return authResult;
  }

  /// Generates digest using from verb response and [secret] and performs a CRAM authentication to
  /// secondary server
  Future<bool> authenticateCram(var secret) async {
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

  ///Executes monitor verb on remote secondary. Result of the monitor verb is processed using [monitorResponseCallback]
  ///[Deprecated] Use [AtClient.notificationService]
  @Deprecated('Use AtClient.notificationService')
  Future<OutboundConnection> monitor(
      String command, Function? notificationCallBack, String privateKey) {
    return MonitorClient(privateKey).executeMonitorVerb(
        command, _atSign, _preference.rootDomain, _preference.rootPort,
        (value) {
      notificationCallBack!(value);
    }, restartCallBack: _restartCallBack);
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
      //TODO getting first ip for now. explore best solution
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

  Future<void> _restartCallBack(
      String command, Function notificationCallBack, String privateKey) async {
    logger.info('auto restarting monitor');
    // ignore: deprecated_member_use_from_same_package
    await monitor(command, notificationCallBack, privateKey);
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
}
