import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart' hide StringBuffer;
import 'package:at_client/at_client_mixins.dart';
import 'package:at_policy/at_policy.dart';
import 'package:at_utils/at_logger.dart';

///
class PolicyServiceImpl with AtClientBindings implements PolicyService {
  @override
  final AtSignLogger logger = AtSignLogger(' PolicyServiceImpl ');

  @override
  late AtClient atClient;

  @override
  final PolicyRequestHandler handler;

  @override
  final String baseNamespace;

  @override
  final String policyRequestNamespace;

  @override
  String get policyAtsign => atClient.getCurrentAtSign()!;

  @override
  final String loggingAtsign;

  @override
  final Set<String> allowList;

  @override
  final bool allowAll;

  @override
  RpcTransformer? requestTransformer;

  @override
  RpcTransformer? responseTransformer;

  late final AtRpc rpc;

  static const JsonEncoder jsonPrettyPrinter = JsonEncoder.withIndent('    ');

  PolicyServiceImpl({
    required this.atClient,
    required this.handler,
    required this.baseNamespace,
    required this.policyRequestNamespace,
    required this.loggingAtsign,
    required this.allowList,
    required this.allowAll,
    this.requestTransformer,
    this.responseTransformer,
  }) {
    rpc = AtRpc(
      atClient: atClient,
      baseNameSpace: baseNamespace,
      domainNameSpace: policyRequestNamespace,
      callbacks: this,
      allowList: allowList,
      allowAll: allowAll,
    );
  }

  @override
  Future<void> run() async {
    rpc.start();

    logger.info('Listening for requests at '
        '${rpc.domainNameSpace}.${rpc.rpcsNameSpace}.${rpc.baseNameSpace}');
  }

  @override
  Future<AtRpcResp> handleRequest(
      AtRpcReq rpcRequest, String fromAtSign) async {
    logger.info('Received request from $fromAtSign: '
        '${jsonPrettyPrinter.convert(rpcRequest.toJson())}');

    Map<String, dynamic> requestPayload = rpcRequest.payload;
    if (requestTransformer != null) {
      requestPayload = await requestTransformer!(requestPayload);
    }
    PolicyRequest policyRequest;

    try {
      policyRequest = PolicyRequest.fromJson(requestPayload);
    } catch (e) {
      final msg = 'Failed PolicyRequest.fromJson: ${e.toString()}';
      logger.severe(msg);
      return AtRpcResp.nack(request: rpcRequest, message: msg);
    }

    try {
      // We will send a 'log' notification to the loggingAtsign
      var logKey = AtKey()
        ..key = '${DateTime.now().millisecondsSinceEpoch}.logs.policy'
        ..sharedBy = policyAtsign
        ..sharedWith = loggingAtsign
        ..namespace = baseNamespace
        ..metadata = (Metadata()
          ..isPublic = false
          ..isEncrypted = true
          ..namespaceAware = true);

      final event = PolicyLogEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        deviceAtsign: fromAtSign,
        policyAtsign: atClient.getCurrentAtSign(),
        devicename: policyRequest.serviceName,
        deviceGroupName: policyRequest.serviceGroupName,
        clientAtsign: policyRequest.clientAtsign,
        eventType: PolicyLogEventType.requestFromDevice,
        eventDetails: {'intents': policyRequest.intents},
        message: '',
      );
      await notify(
        logKey,
        jsonEncode(event),
        checkForFinalDeliveryStatus: false,
        waitForFinalDeliveryStatus: false,
        ttln: Duration(hours: 1),
      );
    } catch (e, st) {
      logger.severe('Failed to send PolicyLogEvent with exception $e'
          '\nStackTrace:'
          '\n$st');
    }

    PolicyResponse policyResponse;
    AtRpcResp rpcResponse;
    try {
      policyResponse = await handler.getPolicyDetails(policyRequest);
      Map<String, dynamic> responsePayload = policyResponse.toJson();
      if (responseTransformer != null) {
        responsePayload = await responseTransformer!(responsePayload);
      }
      rpcResponse = AtRpcResp(
          reqId: rpcRequest.reqId,
          respType: AtRpcRespType.success,
          payload: responsePayload);
    } catch (e) {
      logger.severe('Exception: $e');
      policyResponse = PolicyResponse(
        message: 'Exception: $e',
        policyDetails: [],
      );
      Map<String, dynamic> responsePayload = policyResponse.toJson();
      if (responseTransformer != null) {
        responsePayload = await responseTransformer!(responsePayload);
      }
      rpcResponse = AtRpcResp(
          reqId: rpcRequest.reqId,
          respType: AtRpcRespType.error,
          payload: responsePayload);
    }

    return rpcResponse;
  }

  @override
  Future<void> handleResponse(AtRpcResp response) {
    throw UnimplementedError();
  }
}
