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

/// A provider that says whether it can seal to a recipient in a namespace,
/// and records what it was asked about.
class _ReadinessProvider extends Fake
    implements CryptoProvider, ReportsReadiness {
  _ReadinessProvider(this.id, {required this.ready});

  @override
  final String id;
  final bool ready;
  final List<(String, String)> asked = [];

  @override
  Future<bool> isReadyFor(
      CryptoContext context, String atSign, String namespace) async {
    asked.add((atSign, namespace));
    return ready;
  }
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

  /// How many of the next notifies come back undelivered, as notify() reports
  /// a value it could not seal or send.
  var undelivered = 0;

  setUpAll(() => registerFallbackValue(NotificationParams()));

  /// An RPC on a client configured with [preference], whose notifications are
  /// recorded in [sent].
  AtRpc rpcWith(AtClientPreference preference) {
    atClient = _MockAtClient();
    final notifications = _MockNotificationService();
    sent = [];
    undelivered = 0;
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
      final result = NotificationResult();
      if (undelivered > 0) {
        undelivered--;
        result.atClientException =
            AtClientException.message('could not seal the value');
      }
      return Future.value(result);
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

  AtClientPreference configuredWith(List<CryptoProvider> providers,
          {PqPosture posture = PqPosture.legacy}) =>
      AtClientPreference(posture: posture)
        ..crypto = CryptoConfig(
            defaultProviderId: providers.first.id, providers: providers);

  AtClientPreference configuredFor(List<String> providerIds,
          {PqPosture posture = PqPosture.legacy}) =>
      configuredWith([for (final id in providerIds) _NamedProvider(id)],
          posture: posture);

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

  test('a send is not routed by the provider an earlier send was sealed under',
      () async {
    final rpc = rpcWith(configuredFor(['default-provider', 'sealed']));

    await rpc.sendRequest(
        toAtSign: '@bob', request: request, cryptoProviderId: 'sealed');
    sent.single.atKey.metadata.appMetadata = AppMetadata(providerId: 'sealed');
    await rpc.sendResponse(
        requestUnder(null), request, AtRpcResp.ack(request: request));

    expect(sent.last.atKey.metadata.appMetadata, isNull,
        reason: 'the provider an encryption stamps must not outlive its send');
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

  test(
      'a request from a requester its scheme cannot seal to is answered under '
      'the default', () async {
    final unready = _ReadinessProvider('pq-provider', ready: false);
    final rpc =
        rpcWith(configuredWith([_NamedProvider('default-provider'), unready]));

    await rpc.sendResponse(
        requestUnder('pq-provider'), request, AtRpcResp.ack(request: request));

    expect(unready.asked, [('@bob', 'testing')],
        reason: 'asked about the requester in this RPC\'s namespace, which '
            'is what the response is sealed to');
    expect(sent.single.cryptoProviderId, isNull,
        reason: 'a post-quantum response to a requester with no key there '
            'fails to seal and never arrives; the default is the one it can '
            'open');
  });

  test('and one its scheme can seal to is answered in that scheme', () async {
    final ready = _ReadinessProvider('pq-provider', ready: true);
    final rpc =
        rpcWith(configuredWith([_NamedProvider('default-provider'), ready]));

    await rpc.sendResponse(
        requestUnder('pq-provider'), request, AtRpcResp.ack(request: request));

    expect(ready.asked, hasLength(1),
        reason: 'the control: readiness was asked here too, so the default '
            'above is the no and not a provider never consulted');
    expect(sent.single.cryptoProviderId, 'pq-provider');
  });

  test(
      'a response the notification service could not send is retried, not '
      'counted as sent', () async {
    final rpc = rpcWith(configuredFor(['default-provider', 'pq-provider']));
    undelivered = 1;

    await rpc.sendResponse(
        requestUnder('pq-provider'), request, AtRpcResp.ack(request: request));

    expect(sent.map((p) => p.cryptoProviderId), ['pq-provider', 'pq-provider'],
        reason: 'the first attempt came back undelivered, so a second went '
            'out, and in the same scheme: a legacy fallback this client has '
            'not allowed is not taken for it');
  });

  test('with the legacy fallback allowed, the retry answers under the default',
      () async {
    final rpc = rpcWith(configuredFor(['default-provider', 'pq-provider'])
      ..allowLegacyCryptoFallback = true);
    undelivered = 1;

    await rpc.sendResponse(
        requestUnder('pq-provider'), request, AtRpcResp.ack(request: request));

    expect(sent.map((p) => p.cryptoProviderId), ['pq-provider', null],
        reason: 'the client said a reply that cannot go out in its scheme may '
            'go out legacy, and the response is not lost');
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
