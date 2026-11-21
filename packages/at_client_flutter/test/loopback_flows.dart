import 'dart:io';

import 'package:at_client/at_client_io.dart';
import 'package:at_client_flutter/src/lifecycle/atsign_flows.dart';
import 'package:at_utils/at_progress.dart';

/// The hosts a unit test's atDirectory may be on.
const Set<String> loopbackHosts = {'127.0.0.1', 'localhost', '::1'};

/// A preference naming an atDirectory on the loopback interface, at a port
/// nothing listens on.
Future<AtClientPreference> loopbackPreference() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return AtClientPreference()
    ..rootDomain = InternetAddress.loopbackIPv4.address
    ..rootPort = port;
}

/// The real lifecycle verbs, refusing with [StateError], before anything
/// connects, a preference whose atDirectory is not on the loopback interface.
class LoopbackFlows extends AtsignFlows {
  const LoopbackFlows();

  static AtClientPreference _onLoopback(AtClientPreference preference) {
    if (!loopbackHosts.contains(preference.rootDomain)) {
      throw StateError(
        'A unit test asked for the atDirectory at '
        '${preference.rootDomain}:${preference.rootPort}; give it one on the '
        'loopback interface, such as loopbackPreference()',
      );
    }
    return preference;
  }

  /// [app], [device], [provisioningPollInterval] and [connectBudget] are
  /// passed on only when given, so that one left out takes
  /// `AtsignFlows.activate`'s own default, not a copy of it.
  @override
  Future<AtClient> activate(
    String atSign, {
    required String cramSecret,
    required WrittenAtKeysIo keys,
    required AtClientPreference preference,
    String? namespace,
    AtClientStorage? storage,
    String? app,
    String? device,
    bool? mintLegacyMaterial,
    SigningAlgoType? signingAlgo,
    Duration? provisioningBudget,
    Duration? provisioningPollInterval,
    void Function(ProgressEvent event)? onProgress,
    AtLookUpFactory? lookUps,
    Duration? connectBudget,
  }) async =>
      await Function.apply(
            super.activate,
            [atSign],
            {
              #cramSecret: cramSecret,
              #keys: keys,
              #preference: _onLoopback(preference),
              #namespace: namespace,
              #storage: storage,
              #app: ?app,
              #device: ?device,
              #mintLegacyMaterial: mintLegacyMaterial,
              #signingAlgo: signingAlgo,
              #provisioningBudget: provisioningBudget,
              #provisioningPollInterval: ?provisioningPollInterval,
              #onProgress: onProgress,
              #lookUps: lookUps,
              #connectBudget: ?connectBudget,
            },
          )
          as AtClient;

  @override
  Future<AtClient> open(
    String atSign, {
    required AtKeysIo keys,
    required AtClientPreference preference,
    String? namespace,
    AtClientStorage? storage,
    AtLookUpFactory? lookUps,
    AtServiceFactory? serviceFactory,
    Duration connectBudget = AtConnection.defaultBudget,
  }) async => super.open(
    atSign,
    keys: keys,
    preference: _onLoopback(preference),
    namespace: namespace,
    storage: storage,
    lookUps: lookUps,
    serviceFactory: serviceFactory,
    connectBudget: connectBudget,
  );

  @override
  Future<PendingEnrollment?> resumeEnrollment(
    String atSign, {
    String? app,
    String? device,
    required WrittenAtKeysIo keys,
    required AtClientPreference preference,
    AtLookUpFactory? lookUps,
  }) async => super.resumeEnrollment(
    atSign,
    app: app,
    device: device,
    keys: keys,
    preference: _onLoopback(preference),
    lookUps: lookUps,
  );

  @override
  Future<PendingEnrollment> enroll(
    String atSign, {
    required String otp,
    required String app,
    required String device,
    required Map<String, String> namespaces,
    required WrittenAtKeysIo keys,
    required AtClientPreference preference,
    SigningAlgoType? signingAlgo,
    EnrollmentKeyExchangeMode? keyExchangeMode,
    Duration? apkamKeysExpiry,
    AtLookUpFactory? lookUps,
  }) async => super.enroll(
    atSign,
    otp: otp,
    app: app,
    device: device,
    namespaces: namespaces,
    keys: keys,
    preference: _onLoopback(preference),
    signingAlgo: signingAlgo,
    keyExchangeMode: keyExchangeMode,
    apkamKeysExpiry: apkamKeysExpiry,
    lookUps: lookUps,
  );
}
