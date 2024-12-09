import 'dart:async';

import 'package:at_client/at_client.dart' hide StringBuffer;
import 'package:at_utils/at_logger.dart';
import 'package:at_policy/src/policy/impl.dart';
import 'package:at_policy/src/policy/models.dart';

abstract class PolicyRequestHandler {
  Future<PolicyResponse> getPolicyDetails(PolicyRequest req);
}

typedef RpcTransformer = Future<Map<String, dynamic>> Function(Map<String, dynamic>);

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

  /// For handling requests where the request payload json is not a
  /// [PolicyRequest], but it can be transformed into one. e.g. legacy requests
  RpcTransformer? requestTransformer;

  /// Transform PolicyResponses into some other (e.g. legacy) format
  RpcTransformer? responseTransformer;

  factory PolicyService ({
    required AtClient atClient,
    required String baseNamespace,
    required PolicyRequestHandler handler,
    String policyRequestNamespace = 'requests.policy',
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
