import 'package:at_client/at_client.dart';
import 'package:at_policy/at_policy.dart';
import 'package:at_utils/at_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class MockNotificationService extends Mock implements NotificationService {}

void main() {
  AtSignLogger.root_level = 'shout';
  AtClient atClient = MockAtClient();
  NotificationService notificationService = MockNotificationService();

  setUpAll(() {
    registerFallbackValue(NotificationParams());
    when(() => atClient.getCurrentAtSign()).thenReturn('@policy');
    when(() => atClient.notificationService).thenReturn(notificationService);
    when(() => notificationService.notify(any(),
        checkForFinalDeliveryStatus: any(named: 'checkForFinalDeliveryStatus'),
        waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
        onSuccess: any(named: 'onSuccess'),
        onError: any(named: 'onError'),
        onSentToSecondary:
            any(named: 'onSentToSecondary'))).thenAnswer((_) async {
      return NotificationResult();
    });
  });

  late PolicyService ps;

  setUp(() {
    ps = PolicyService(
      atClient: atClient,
      handler: TestHandler(),
      baseNamespace: 'test',
      policyRequestNamespace: 'policy',
      loggingAtsign: '@alice',
      allowList: {},
      allowAll: true,
    );
  });

  AtRpcReq createRpcPolicyRequest(List<PolicyIntent> intents) {
    PolicyRequest req = PolicyRequest(
      serviceAtsign: '@service',
      serviceName: 'service_1',
      serviceGroupName: 'test_services',
      clientAtsign: '@alice',
      intents: intents,
    );
    return AtRpcReq(
      reqId: DateTime.now().microsecondsSinceEpoch,
      payload: req.toJson(),
    );
  }

  test('Test happy path', () async {
    AtRpcResp rpcResp = await ps.handleRequest(
        createRpcPolicyRequest([
          PolicyIntent(intent: 'emote', params: {'emotion': 'happiness'})
        ]),
        '@service');
    PolicyResponse pr = PolicyResponse.fromJson(rpcResp.payload);
    expect(pr.policyDetails.length, 1);
    expect(pr.policyDetails[0].intent, 'emote');
    expect(pr.policyDetails[0].info, isNotNull);
    expect(pr.policyDetails[0].info, isNotEmpty);
    expect(pr.policyDetails[0].info['allowed'], true);
    expect(pr.policyDetails[0].info['message'], 'Laughter is encouraged');
  });

  test('Test negative response', () async {
    AtRpcResp rpcResp = await ps.handleRequest(
        createRpcPolicyRequest([
          PolicyIntent(intent: 'emote', params: {'emotion': 'anger'})
        ]),
        '@service');
    PolicyResponse pr = PolicyResponse.fromJson(rpcResp.payload);
    expect(pr.policyDetails.length, 1);
    expect(pr.policyDetails[0].intent, 'emote');
    expect(pr.policyDetails[0].info, isNotNull);
    expect(pr.policyDetails[0].info, isNotEmpty);
    expect(pr.policyDetails[0].info['allowed'], false);
    expect(pr.policyDetails[0].info['message'], 'Anger is discouraged');
  });

  test('Test null request', () async {
    AtRpcResp rpcResp = await ps.handleRequest(
        AtRpcReq(
          reqId: DateTime.now().microsecondsSinceEpoch,
          payload: {},
        ),
        '@service');
    expect(rpcResp.respType, AtRpcRespType.nack);
    expect(rpcResp.message, contains('Failed PolicyRequest.fromJson'));
  });

  test('Test malformed request', () async {
    AtRpcResp rpcResp = await ps.handleRequest(
        AtRpcReq(
          reqId: DateTime.now().microsecondsSinceEpoch,
          payload: {'foo': 12345, 'bar': false},
        ),
        '@service');
    expect(rpcResp.respType, AtRpcRespType.nack);
    expect(rpcResp.message, contains('Failed PolicyRequest.fromJson'));
  });

  test('Test unknown intent', () async {
    AtRpcResp rpcResp = await ps.handleRequest(
        createRpcPolicyRequest([PolicyIntent(intent: 'dance', params: {})]),
        '@service');
    expect(rpcResp.respType, AtRpcRespType.error);
    expect(rpcResp.payload['message'], contains('Unknown intent: dance'));
  });
}

class TestHandler implements PolicyRequestHandler {
  @override
  Future<PolicyResponse> getPolicyDetails(PolicyRequest req) async {
    if (req.intents.isEmpty) {
      throw ArgumentError('No intents were supplied in the PolicyRequest');
    }
    PolicyResponse resp = PolicyResponse(message: '', policyDetails: []);
    for (final intent in req.intents) {
      if (intent.params == null) {
        throw ArgumentError(
            'No parameters supplied with intent ${intent.intent}');
      }
      switch (intent.intent) {
        case 'emote':
          String? emotion = intent.params!['emotion'];
          if (emotion == null) {
            throw ArgumentError('the "emotion" parameter is required'
                ' for the ${intent.intent} intent');
          }
          switch (emotion) {
            case 'happiness':
              resp.policyDetails.add(PolicyDetail(
                intent: intent.intent,
                info: {'allowed': true, 'message': 'Laughter is encouraged'},
              ));
            case 'anger':
              resp.policyDetails.add(PolicyDetail(
                intent: intent.intent,
                info: {'allowed': false, 'message': "Anger is discouraged"},
              ));
            default:
              resp.policyDetails.add(PolicyDetail(
                intent: intent.intent,
                info: {
                  'allowed': false,
                  'message': 'Expressing $emotion is not allowed'
                },
              ));
          }
        default:
          throw ArgumentError('Unknown intent: ${intent.intent}');
      }
    }
    return resp;
  }
}
