import 'dart:async';

import 'package:at_client/at_client.dart' hide StringBuffer;
import 'package:at_utils/at_logger.dart';
import 'package:at_policy/src/policy/impl.dart';
import 'package:at_policy/src/policy/models.dart';

abstract class PolicyRequestHandler {
  Future<PolicyResponse> getPolicyDetails(PolicyRequest req);
}

/// - Listens for requests for policy info from services
/// - Returns info for each of the policy intents in the request.
abstract class PolicyService implements AtRpcCallbacks {
  abstract final AtSignLogger logger;

  /// The [AtClient] used to communicate with things using this PolicyService
  AtClient get atClient;

  PolicyRequestHandler get handler;

  /// Starts the service
  Future<void> run();

  String get baseNamespace;

  String get policyRequestNamespace;

  String get policyAtsign;

  String get loggingAtsign;

  Set<String> get allowList;

  bool get allowAll;

  factory PolicyService({
    required AtClient atClient,
    required String baseNamespace,
    required PolicyRequestHandler handler,
    String policyRequestNamespace = 'policy',
    String? loggingAtsign,
    Set<String>? allowList,
    bool allowAll = true,
  }) {
    return PolicyServiceImpl(
      atClient: atClient,
      handler: handler,
      baseNamespace: baseNamespace,
      policyRequestNamespace: policyRequestNamespace,
      loggingAtsign: loggingAtsign ?? atClient.getCurrentAtSign()!,
      allowList: allowList ?? {},
      allowAll: allowAll,
    );
  }
}
