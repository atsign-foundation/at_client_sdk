import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/outbound_connection.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_utils.dart';

/// Contains methods used to execute verbs on remote secondary server of the atSign.
class RemoteSecondary implements Secondary {
  var logger = AtSignLogger('RemoteSecondary');

  String _atSign;

  var _preference;

  AtLookupImpl atLookUp;

  AtLookupSync atLookupSync;

  RemoteSecondary(String atSign, AtClientPreference preference,
      {String privateKey}) {
    _atSign = AtUtils.formatAtSign(atSign);
    _preference = preference;
    privateKey ??= preference.privateKey;
    atLookUp = AtLookupImpl(atSign, preference.rootDomain, preference.rootPort,
        privateKey: privateKey, cramSecret: preference.cramSecret);
    atLookupSync = AtLookupSync(
        atSign, preference.rootDomain, preference.rootPort,
        privateKey: atLookUp.privateKey, cramSecret: preference.cramSecret);
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
    if (verbResult != null) {
      verbResult = verbResult.replaceFirst('data:', '');
    }
    return verbResult;
  }

  Future<String> executeCommand(String atCommand, {bool auth = false}) async {
    var verbResult;
    verbResult = await atLookUp.executeCommand(atCommand, auth: auth);
    return verbResult;
  }

  void addStreamData(List<int> data) {
    atLookUp.connection.getSocket().add(data);
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
  Future<String> sync(int lastSyncedId,
      {String privateKey, String regex, Function syncCallback}) async {
    var atCommand = 'sync:$lastSyncedId';
    var regexString = (regex != null && regex != 'null' && regex.isNotEmpty)
        ? ':$regex'
        : ((_preference.syncRegex != null && _preference.syncRegex.isNotEmpty)
            ? ':${_preference.syncRegex}'
            : '');
    atCommand += '$regexString\n';
    atLookupSync.syncCallback = syncCallback;
    return await atLookupSync.executeCommand(atCommand, auth: true);
  }

  ///Executes monitor verb on remote secondary. Result of the monitor verb is processed using [monitorResponseCallback].
  Future<OutboundConnection> monitor(
      String command, Function notificationCallBack, String privateKey) {
    return MonitorClient(privateKey).executeMonitorVerb(
        command, _atSign, _preference.rootDomain, _preference.rootPort,
        (value) {
      notificationCallBack(value);
    }, restartCallBack: _restartCallBack);
  }

  Future<void> _restartCallBack(
      String command, Function notificationCallBack, String privateKey) async {
    logger.finer('auto restarting monitor');
    await monitor(command, notificationCallBack, privateKey);
  }
}
