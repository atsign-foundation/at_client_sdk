import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtClient extends Mock implements AtClient {}

class _MockNotificationService extends Mock implements NotificationService {}

/// A provider known only by its id, which is all a lookup reads.
class _NamedProvider extends Fake implements CryptoProvider {
  _NamedProvider(this.id);

  @override
  final String id;
}

class _Callbacks implements AtRpcCallbacks {
  @override
  Future<AtRpcResp> handleRequest(AtRpcReq request, String fromAtSign) async =>
      AtRpcResp.ack(request: request);

  @override
  Future<void> handleResponse(AtRpcResp response) async {}
}

/// The scheme an RPC request is sent in, and the one its response answers in.
void main() {
  AtSignLogger.root_level = 'shout';

  late AtClient atClient;
  late List<NotificationParams> sent;

  setUpAll(() => registerFallbackValue(NotificationParams()));

  /// An RPC on a client configured with [preference], whose notifications are
  /// recorded in [sent].
  AtRpc rpcWith(AtClientPreference preference) {
    atClient = _MockAtClient();
    final notifications = _MockNotificationService();
    sent = [];
    when(() => atClient.getCurrentAtSign()).thenReturn('@alice');
    when(() => atClient.getPreferences()).thenReturn(preference);
    when(() => atClient.notificationService).thenReturn(notifications);
    when(() => atClient.isStopped).thenReturn(false);
    when(() => notifications.currentListenerState)
        .thenReturn(NotificationListenerState.listening);
    when(() => notifications.currentListenerStateStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => notifications.subscribe(
            regex: any(named: 'regex'),
            shouldDecrypt: any(named: 'shouldDecrypt')))
        .thenAnswer((_) => const Stream.empty());
    when(() => notifications.notify(any(),
        checkForFinalDeliveryStatus: any(named: 'checkForFinalDeliveryStatus'),
        waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
        onSuccess: any(named: 'onSuccess'),
        onError: any(named: 'onError'),
        onSentToSecondary: any(named: 'onSentToSecondary'))).thenAnswer((inv) {
      sent.add(inv.positionalArguments[0] as NotificationParams);
      return Future.value(NotificationResult());
    });
    return AtRpc(
        atClient: atClient,
        baseNameSpace: 'testing',
        domainNameSpace: 'schemes',
        callbacks: _Callbacks(),
        allowList: {},
        isClient: true,
        isServer: true);
  }

  AtClientPreference configuredFor(List<String> providerIds,
          {PqPosture posture = PqPosture.legacy}) =>
      AtClientPreference(posture: posture)
        ..crypto = CryptoConfig(
            defaultProviderId: providerIds.first,
            providers: [for (final id in providerIds) _NamedProvider(id)]);

  AtNotification requestUnder(String? providerId) => AtNotification.empty()
    ..from = '@bob'
    ..metadata = (Metadata()
      ..appMetadata =
          providerId == null ? null : AppMetadata(providerId: providerId));

  final request = AtRpcReq.create({'q': 1});

  test('a request goes out under the provider it is given, else the default',
      () async {
    final rpc = rpcWith(configuredFor(['default-provider']));

    await rpc.sendRequest(
        toAtSign: '@bob', request: request, cryptoProviderId: 'chosen');
    await rpc.sendRequest(toAtSign: '@bob', request: request);

    expect(sent.map((p) => p.cryptoProviderId), ['chosen', null]);
  });

  test('a response answers in the scheme its request arrived in', () async {
    final rpc =
        rpcWith(configuredFor(['default-provider', 'request-provider']));

    await rpc.sendResponse(requestUnder('request-provider'), request,
        AtRpcResp.ack(request: request));

    expect(sent.single.cryptoProviderId, 'request-provider',
        reason: 'the provider the request arrived under, not this client\'s '
            'default');
    expect(sent.single.atKey.sharedWith, '@bob');
  });

  test('a request that arrived legacy is answered legacy', () async {
    final rpc = rpcWith(configuredFor(['default-provider']));

    await rpc.sendResponse(
        requestUnder(null), request, AtRpcResp.ack(request: request));

    expect(sent.single.cryptoProviderId, legacyCryptoProviderId,
        reason: 'an older client stamps nothing and can read only legacy');
  });

  test('a scheme this client cannot write falls back to its default', () async {
    final refusesLegacy = rpcWith(
        configuredFor(['default-provider'], posture: PqPosture.pqActive));
    await refusesLegacy.sendResponse(
        requestUnder(null), request, AtRpcResp.ack(request: request));
    expect(sent.single.cryptoProviderId, isNull,
        reason: 'a posture that refuses legacy writes answers in its own '
            'default rather than failing to answer at all');

    final unconfigured = rpcWith(configuredFor(['default-provider']));
    await unconfigured.sendResponse(requestUnder('not-configured-here'),
        request, AtRpcResp.ack(request: request));
    expect(sent.single.cryptoProviderId, isNull,
        reason: 'a provider this client does not have cannot seal the '
            'answer');
  });

  test('a call goes out under the provider it is given', () async {
    final preference = configuredFor(['default-provider']);
    rpcWith(preference);
    final client = AtRpcClient(
        serverAtsign: '@bob',
        atClient: atClient,
        baseNameSpace: 'testing',
        domainNameSpace: 'schemes');

    unawaited(client.call({'q': 2}, cryptoProviderId: 'chosen').then((_) {},
        onError: (_) {}));
    await Future<void>.delayed(Duration(milliseconds: 50));

    expect(sent.map((p) => p.cryptoProviderId), ['chosen']);
  });
}
