import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/outbound_connection.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_utils.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

/// Contains methods used to execute verbs on remote secondary server of the atSign.
class RemoteSecondary implements Secondary {
  var logger = AtSignLogger('RemoteSecondary');

  late String _atSign;

  late var _preference;

  late AtLookupImpl atLookUp;

  RemoteSecondary(String atSign, AtClientPreference preference,
      {String? privateKey}) {
    _atSign = AtUtils.formatAtSign(atSign)!;
    _preference = preference;
    privateKey ??= preference.privateKey;
    atLookUp = AtLookupImpl(atSign, preference.rootDomain, preference.rootPort,
        privateKey: privateKey, cramSecret: preference.cramSecret);
  }

  /// Executes the command returned by [VerbBuilder] build command on a remote secondary server.
  /// Optionally [privateKey] is passed for verb builders which require authentication.
  @override
  Future<String> executeVerb(VerbBuilder builder, {sync = false}) async {
    var verbResult;
    verbResult = await atLookUp.executeVerb(builder);
    return verbResult;
  }

  Future<String> executeAndParse(VerbBuilder builder, {sync = false}) async {
    var verbResult = await executeVerb(builder);
    verbResult = verbResult.replaceFirst('data:', '');
    return verbResult;
  }

  Future<String?> executeCommand(String atCommand, {bool auth = false}) async {
    var verbResult;
    verbResult = await atLookUp.executeCommand(atCommand, auth: auth);
    return verbResult;
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
  Future<bool> authenticate_cram(var secret) async {
    var authResult = await atLookUp.authenticate_cram(secret);
    return authResult;
  }

  /// Executes sync verb on the remote server. Return commit entries greater than [lastSyncedId].
  Future<String?> sync(int? lastSyncedId, {String? regex}) async {
    var syncVerbBuilder = SyncVerbBuilder()
      ..commitId = lastSyncedId
      ..regex = regex;

    var atCommand = syncVerbBuilder.buildCommand();
    return atLookUp.executeCommand(atCommand, auth: true);
  }

  ///Executes monitor verb on remote secondary. Result of the monitor verb is processed using [monitorResponseCallback].
  Future<OutboundConnection> monitor(
      String command, Function? notificationCallBack, String privateKey) {
    return MonitorClient(privateKey).executeMonitorVerb(
        command, _atSign, _preference.rootDomain, _preference.rootPort,
        (value) {
      notificationCallBack!(value);
    }, restartCallBack: _restartCallBack);
  }

  Future<bool> isAvailable() async {
    try {
      var secondaryUrl = await AtLookupImpl.findSecondary(
          _atSign, _preference.rootDomain, _preference.rootPort);
      var secondaryInfo = AtClientUtil.getSecondaryInfo(secondaryUrl);
      var host = secondaryInfo[0];
      var port = secondaryInfo[1];
      var internetAddress = await InternetAddress.lookup(host);
      //#TODO getting first ip for now. explore best solution
      var addressCheckOptions =
          AddressCheckOptions(internetAddress[0], port: int.parse(port));
      return (await InternetConnectionChecker()
              .isHostReachable(addressCheckOptions))
          .isSuccess;
    } on Exception catch (e) {
      logger.severe('Secondary server unavailable ${e.toString}');
    } on Error catch (e) {
      logger.severe('Secondary server unavailable ${e.toString}');
    }
    return false;
  }

  Future<void> _restartCallBack(
      String command, Function notificationCallBack, String privateKey) async {
    logger.info('auto restarting monitor');
    await monitor(command, notificationCallBack, privateKey);
  }
}
