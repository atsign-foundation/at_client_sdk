import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/transformer/response_transformer/notification_response_transformer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/transport.dart';

const _owner = '@alice';
const _namespace = 'sshrvd';
const _kid = 'gen-1';
const _ciphertext = 'sealed';
const _plaintext = '{"ipaddr":"127.0.0.1","port":443}';

class _FakeMonitor extends Fake implements Monitor {
  @override
  NotificationListenerState currentState =
      NotificationListenerState.notConnected;
  @override
  NotificationListenerState targetState =
      NotificationListenerState.notConnected;
  @override
  Future<void> start({int? lastNotificationTime}) async {}
  @override
  void stop() {}
  @override
  Stream<NotificationListenerState> get currentStateStream =>
      const Stream.empty();
}

/// Opens only the ciphertext and refuses anything else, the way a base64
/// decode refuses plaintext, so a value decrypted twice fails as it does in
/// the field. Counts every attempt.
class _StrictProvider extends CryptoProvider {
  @override
  final String id = 'strict-provider';
  int decrypts = 0;

  /// While false, decryption waits for a key that has not been filed yet.
  bool filed = true;

  /// Runs at the start of every decryption.
  void Function()? onDecrypt;

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String value) async {
    decrypts++;
    onDecrypt?.call();
    if (!filed) {
      throw NskeyPrivateUnavailableException(
          _owner, _namespace, _kid, 'not yet received that generation');
    }
    if (value != _ciphertext) {
      throw FormatException('Invalid character (at character 1)', value);
    }
    return _plaintext;
  }

  @override
  Future<String> encrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      value;
}

/// A ring that emits the filing signal on demand.
class _SignallingRing extends InMemoryNskeyKeyRing
    implements SignalsPrivateFiling {
  final _controller = StreamController<FiledNskeyPrivate>.broadcast();

  @override
  Stream<FiledNskeyPrivate> get privatesFiled => _controller.stream;

  void announce() =>
      _controller.add((owner: _owner, namespace: _namespace, nskeyKid: _kid));

  Future<void> dispose() => _controller.close();
}

String _frame(String key,
        {MessageTypeEnum messageType = MessageTypeEnum.key,
        String? pubKeyHash}) =>
    'notification: ${jsonEncode({
          'id': 'n-${key.hashCode}',
          'key': key,
          'from': _owner,
          'to': _owner,
          'epochMillis': DateTime.now().millisecondsSinceEpoch,
          'value': _ciphertext,
          'operation': 'update',
          'messageType': messageType.toString(),
          AtConstants.isEncrypted: true,
          'metadata': {
            AtConstants.appMetadata: Metadata.encodeAppMetadata(
                AppMetadata(providerId: 'strict-provider')),
            if (pubKeyHash != null)
              AtConstants.sharedWithPublicKeyHash:
                  jsonEncode({'hash': pubKeyHash, 'hashingAlgo': 'sha256'}),
          },
        })}\n';

/// A notification is decrypted at most once, however many subscribers
/// receive it, and each subscriber gets its own copy of the result.
///
/// The notification is delivered to each subscriber in turn. A subscriber must
/// neither be handed a value another subscriber already decrypted, nor decrypt
/// a notification its regex does not match.
void main() {
  late MockAtClientImpl atClient;
  late _StrictProvider provider;
  late _SignallingRing ring;
  late NotificationServiceImpl service;

  const key = '@alice:discover_response.$_namespace@alice';

  setUpAll(() => registerFallbackValue(FakeAtKey()));

  setUp(() async {
    atClient = MockAtClientImpl();
    provider = _StrictProvider();
    ring = _SignallingRing();
    when(() => atClient.getCurrentAtSign()).thenReturn(_owner);
    when(() => atClient.atSign).thenReturn(_owner.toAtsign());
    when(() => atClient.getPreferences()).thenReturn(AtClientPreference()
      ..namespace = _namespace
      ..crypto = CryptoConfig(
        defaultProviderId: provider.id,
        providers: [provider],
        keyRing: ring,
      ));
    // NOTE: the service writes the last-received notification id after every
    // notification it accepts; unstubbed, that write fails on every delivery.
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((_) async => true);
    service = await NotificationServiceImpl.create(atClient,
        monitor: _FakeMonitor(),
        secondaryAddressFinder: defaultAtDirectory) as NotificationServiceImpl;
  });

  tearDown(() async {
    service.stopAllSubscriptions();
    await ring.dispose();
  });

  Future<void> deliver(String frame) async {
    await service.handleNotificationReceipt(frame);
    await Future<void>.delayed(Duration.zero);
  }

  test(
      'two subscribers matching one encrypted notification both get the '
      'plaintext, from one decryption', () async {
    final first = <String?>[];
    final second = <String?>[];
    service
        .subscribe(regex: r'discover_response', shouldDecrypt: true)
        .listen((n) => first.add(n.value));
    service
        .subscribe(regex: r'\.sshrvd@alice', shouldDecrypt: true)
        .listen((n) => second.add(n.value));

    await deliver(_frame(key));

    expect(first, [_plaintext]);
    expect(second, [_plaintext],
        reason: 'the second subscriber must get the plaintext too, not a '
            'failed attempt to decrypt the value the first one decrypted');
    expect(provider.decrypts, 1,
        reason: 'a notification is decrypted once, whatever the number of '
            'subscribers receiving it');
  });

  test('a subscriber whose regex does not match costs a later one nothing',
      () async {
    final other = <String?>[];
    final matching = <String?>[];
    service
        .subscribe(regex: r'discover_response\.sshrvd@bob', shouldDecrypt: true)
        .listen((n) => other.add(n.value));
    service
        .subscribe(
            regex: r'discover_response\.sshrvd@alice', shouldDecrypt: true)
        .listen((n) => matching.add(n.value));

    await deliver(_frame(key));

    expect(other, isEmpty);
    expect(matching, [_plaintext],
        reason: 'a subscriber registered earlier for another sender must not '
            'take this notification from the one it was sent for');
    expect(provider.decrypts, 1);
  });

  test('a notification no subscriber matches is not decrypted', () async {
    service
        .subscribe(regex: r'discover_response\.sshrvd@bob', shouldDecrypt: true)
        .listen((_) {});

    await deliver(_frame(key));

    expect(provider.decrypts, 0,
        reason: 'decrypting for a subscriber that does not receive the '
            'notification is wasted work, and its failure is reported as a '
            'dropped notification for a subscriber that never wanted it');
  });

  test('a subscriber that does not decrypt still gets the ciphertext',
      () async {
    final decrypting = <String?>[];
    final raw = <String?>[];
    service
        .subscribe(regex: r'discover_response', shouldDecrypt: true)
        .listen((n) => decrypting.add(n.value));
    service
        .subscribe(regex: r'discover_response\.sshrvd')
        .listen((n) => raw.add(n.value));

    await deliver(_frame(key));

    expect(decrypting, [_plaintext]);
    expect(raw, [_ciphertext],
        reason: 'shouldDecrypt: false asks for the value as it arrived, '
            'whatever an earlier subscriber did with its own copy');
  });

  group('Given two subscribers on one client asking for the same regex', () {
    test(
        'when the first asks for the value as it arrived and the second for it '
        'decrypted, then each gets what it asked for, from one decryption',
        () async {
      final raw = <String?>[];
      final decrypting = <String?>[];
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: false)
          .listen((n) => raw.add(n.value));
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((n) => decrypting.add(n.value));

      await deliver(_frame(key));

      expect(raw, [_ciphertext]);
      expect(decrypting, [_plaintext],
          reason: 'shouldDecrypt: true asks for the value decrypted, whatever '
              'an earlier subscription on the same regex asked for');
      expect(provider.decrypts, 1);
    });

    test(
        'when the first asks for it decrypted and the second for it as it '
        'arrived, then each gets what it asked for', () async {
      final decrypting = <String?>[];
      final raw = <String?>[];
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((n) => decrypting.add(n.value));
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: false)
          .listen((n) => raw.add(n.value));

      await deliver(_frame(key));

      expect(decrypting, [_plaintext]);
      expect(raw, [_ciphertext],
          reason: 'shouldDecrypt: false asks for the value as it arrived, so '
              'a subscriber that asked for that must not be handed plaintext');
      expect(provider.decrypts, 1);
    });

    test(
        'when both ask for the same decryption, then each listener has a '
        'subscription of its own and both receive the notification, from one '
        'decryption', () async {
      final first = <String?>[];
      final second = <String?>[];
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((n) => first.add(n.value));
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((n) => second.add(n.value));

      await deliver(_frame(key));

      expect(service.getStreamListenersCount(), 2);
      expect(first, [_plaintext]);
      expect(second, [_plaintext]);
      expect(provider.decrypts, 1);
    });

    test(
        'when the decrypting one must wait for its key, then the raw one is '
        'served at once and the decrypting one is re-driven with the plaintext '
        'once the key is filed', () async {
      provider.filed = false;
      final raw = <String?>[];
      final decrypting = <String?>[];
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: false)
          .listen((n) => raw.add(n.value));
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((n) => decrypting.add(n.value));

      await deliver(_frame(key));
      expect(raw, [_ciphertext]);
      expect(decrypting, isEmpty,
          reason: 'the decrypting subscriber waits for its key rather than '
              'being handed the value as it arrived');
      expect(service.parkedCount, 1);

      provider.filed = true;
      ring.announce();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(decrypting, [_plaintext]);
      expect(raw, [_ciphertext],
          reason: 'the re-drive is for the subscriber that waited, not the '
              'one already served');
    });

    test(
        'when both ask for the same decryption and the first changes the '
        'notification it receives, then the second sees it as it arrived',
        () async {
      final second = <String?>[];
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((n) => n.value = 'changed by the first subscriber');
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((n) => second.add(n.value));

      await deliver(_frame(key));

      expect(second, [_plaintext],
          reason: 'each listener gets its own copy of the notification, '
              'whatever another with the same regex and decryption does to its '
              'own');
    });

    test(
        'when both ask for the same decryption and the first changes the '
        'metadata of the notification it receives, then the second sees it '
        'as it arrived', () async {
      final second = <(String?, String?)>[];
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((n) {
        n.metadata!.encKeyName = 'changed by the first subscriber';
        n.metadata!.appMetadata!.providerId = 'changed-by-first';
      });
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((n) => second.add(
              (n.metadata!.encKeyName, n.metadata!.appMetadata!.providerId)));

      await deliver(_frame(key));

      expect(second, [(null, 'strict-provider')],
          reason: 'a subscription\'s copy of a notification carries its own '
              'metadata, app metadata included');
    });

    test(
        'when both ask for the same decryption and the first changes the '
        'public key hash of the notification it receives, then the second '
        'sees it as it arrived', () async {
      final second = <String?>[];
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((n) => n.metadata!.pubKeyHash!.hash = 'changed-by-first');
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((n) => second.add(n.metadata!.pubKeyHash!.hash));

      await deliver(_frame(key, pubKeyHash: 'arrived'));

      expect(second, ['arrived'],
          reason: 'a subscription\'s copy of a notification carries its own '
              'public key hash');
    });

    test(
        'when both wait for their key on as many notifications as the park '
        'holds, then none is dropped', () async {
      final maxParked = NotificationServiceImpl.maxParked;
      addTearDown(() => NotificationServiceImpl.maxParked = maxParked);
      NotificationServiceImpl.maxParked = 2;
      provider.filed = false;
      final dropped = <DroppedNotification>[];
      service.droppedEvents.listen(dropped.add);
      for (var i = 0; i < 2; i++) {
        service
            .subscribe(regex: r'discover_response', shouldDecrypt: true)
            .listen((_) {});
      }

      await deliver(_frame(key));
      await deliver(_frame('@alice:discover_response_2.$_namespace@alice'));

      expect(dropped, isEmpty,
          reason: 'the park bound counts notifications, so the number of '
              'subscriptions waiting on each does not shrink it');
      expect(service.parkedCount, 4);
    });
  });

  group('Given three subscribers matching one notification', () {
    test(
        'when the first cancels on receiving it, then the third still '
        'receives it', () async {
      final third = <String?>[];
      late final StreamSubscription<AtNotification> first;
      first = service
          .subscribe(regex: r'discover_response')
          .listen((_) => first.cancel());
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((_) {});
      service
          .subscribe(regex: r'discover_response')
          .listen((n) => third.add(n.value));

      await deliver(_frame(key));

      expect(third, [_ciphertext],
          reason: 'a subscription released during a delivery must not end '
              'that delivery for the subscriptions after it');
    });
  });

  test('each subscriber gets its own copy', () async {
    final second = <String?>[];
    service
        .subscribe(regex: r'discover_response', shouldDecrypt: true)
        .listen((n) => n.value = 'changed by the first subscriber');
    service
        .subscribe(regex: r'\.sshrvd@alice', shouldDecrypt: true)
        .listen((n) => second.add(n.value));

    await deliver(_frame(key));

    expect(second, [_plaintext],
        reason: 'sharing one decryption must not mean sharing one mutable '
            'object between subscribers');
  });

  test(
      'subscribers parked on one notification are re-driven from one '
      'decryption', () async {
    provider.filed = false;
    final first = <String?>[];
    final second = <String?>[];
    service
        .subscribe(regex: r'discover_response', shouldDecrypt: true)
        .listen((n) => first.add(n.value));
    service
        .subscribe(regex: r'\.sshrvd@alice', shouldDecrypt: true)
        .listen((n) => second.add(n.value));

    await deliver(_frame(key));
    expect(service.parkedCount, 2, reason: 'precondition: both parked');
    expect(provider.decrypts, 1,
        reason: 'the attempt that parked them was made once');

    provider.filed = true;
    ring.announce();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(first, [_plaintext]);
    expect(second, [_plaintext]);
    expect(provider.decrypts, 2,
        reason: 'one failed attempt and one re-drive, not one per subscriber');
  });

  test('transforming a notification leaves the one passed in unchanged',
      () async {
    // Pinned on the transformer itself: which subscriber is served first
    // follows the subscription map's hash order, so a test through the
    // service cannot be sure a later subscriber sees an in-place write.
    final arrived =
        AtNotification.fromJson(jsonDecode(_frame(key).substring(14)));

    final transformed =
        await NotificationResponseTransformer(atClient).transform(Tuple()
          ..one = arrived
          ..two = (NotificationConfig()
            ..regex = '.*'
            ..shouldDecrypt = true));

    expect(transformed.value, _plaintext);
    expect(arrived.value, _ciphertext,
        reason: 'the notification is handed on to other subscribers after '
            'this transform, and must reach them as it arrived');
    expect(identical(transformed, arrived), isFalse);
  });

  test('control: a lone matching subscriber decrypts once', () async {
    // Without this arm the counts above pass for a delivery that decrypts
    // nothing at all.
    final seen = <String?>[];
    service
        .subscribe(regex: r'discover_response', shouldDecrypt: true)
        .listen((n) => seen.add(n.value));

    await deliver(_frame(key));

    expect(seen, [_plaintext]);
    expect(provider.decrypts, 1);
  });

  group('Given a decrypting subscription waiting for its key', () {
    test(
        'when one of two subscriptions waiting on a notification cancels, then '
        'only the other stays parked', () async {
      provider.filed = false;
      final leaving = service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((_) {});
      service
          .subscribe(regex: r'\.sshrvd@alice', shouldDecrypt: true)
          .listen((_) {});
      await deliver(_frame(key));
      expect(service.parkedCount, 2, reason: 'precondition: both parked');

      await leaving.cancel();

      expect(service.parkedCount, 1,
          reason: 'a subscription releases the notifications parked for it '
              'when its listener cancels, and only those');
    });

    test(
        'when its only listener cancels, then its parked notification is '
        'reported as dropped', () async {
      provider.filed = false;
      final dropped = <DroppedNotification>[];
      service.droppedEvents.listen(dropped.add);
      final leaving = service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((_) {});
      await deliver(_frame(key));
      expect(service.parkedCount, 1, reason: 'precondition: it parked');

      await leaving.cancel();
      await Future<void>.delayed(Duration.zero);

      expect(dropped.map((d) => d.key), [key],
          reason: 'a parked notification given up with its subscription is '
              'reported, as every other notification this service gives up '
              'on is');
    });

    test(
        'when another subscription changes the metadata of the same '
        'notification, then it is still delivered once the key is filed',
        () async {
      provider.filed = false;
      final delivered = Completer<String?>();
      final droppedOne = Completer<DroppedNotification>();
      service.droppedEvents.listen((d) {
        if (!droppedOne.isCompleted) droppedOne.complete(d);
      });
      service.subscribe(regex: r'discover_response').listen(
          (n) => n.metadata!.appMetadata!.providerId = 'not-a-provider');
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((n) => delivered.complete(n.value));
      await deliver(_frame(key));
      expect(service.parkedCount, 1, reason: 'precondition: it parked');

      provider.filed = true;
      ring.announce();
      final outcome =
          await Future.any<Object?>([delivered.future, droppedOne.future])
              .timeout(const Duration(seconds: 10));

      expect(outcome, _plaintext,
          reason: 'what one subscription does to its copy must not change '
              'the notification another is still waiting to receive');
    });

    test(
        'when another subscription changes the public key hash of the same '
        'notification, then it is delivered as it arrived once the key is '
        'filed', () async {
      provider.filed = false;
      final delivered = Completer<String?>();
      service
          .subscribe(regex: r'discover_response')
          .listen((n) => n.metadata!.pubKeyHash!.hash = 'changed-by-other');
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((n) => delivered.complete(n.metadata!.pubKeyHash!.hash));
      await deliver(_frame(key, pubKeyHash: 'arrived'));
      expect(service.parkedCount, 1, reason: 'precondition: it parked');

      provider.filed = true;
      ring.announce();

      expect(await delivered.future.timeout(const Duration(seconds: 10)),
          'arrived',
          reason: 'a parked notification is held as it arrived, whatever '
              'another subscription does to its own copy');
    });

    test(
        'when another subscription waiting on the same notification cancels '
        'while this one is re-driven, then its notification is reported as '
        'dropped', () async {
      provider.filed = false;
      final dropped = <DroppedNotification>[];
      service.droppedEvents.listen(dropped.add);
      final delivered = Completer<String?>();
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((n) => delivered.complete(n.value));
      final leaving = service
          .subscribe(regex: r'\.sshrvd@alice', shouldDecrypt: true)
          .listen((_) {});
      await deliver(_frame(key));
      expect(service.parkedCount, 2, reason: 'precondition: both parked');

      provider.filed = true;
      provider.onDecrypt = () {
        provider.onDecrypt = null;
        leaving.cancel();
      };
      ring.announce();
      expect(await delivered.future.timeout(const Duration(seconds: 10)),
          _plaintext,
          reason: 'precondition: the re-drive ran');
      await Future<void>.delayed(Duration.zero);

      expect(dropped.map((d) => d.key), [key],
          reason: 'a parked notification given up because its listener '
              'cancelled during the re-drive is reported, as one given up at '
              'any other moment is');
    });

    test(
        'when it is cancelled while its notification is being decrypted, then '
        'nothing is parked for it', () async {
      provider.filed = false;
      final dropped = <DroppedNotification>[];
      service.droppedEvents.listen(dropped.add);
      late final StreamSubscription<AtNotification> leaving;
      leaving = service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((_) {});
      provider.onDecrypt = () => leaving.cancel();

      await deliver(_frame(key));

      expect(provider.decrypts, 1, reason: 'precondition: decryption began');
      expect(service.parkedCount, 0,
          reason: 'a notification parked for a released subscription is held '
              'for nobody, and nothing releases it');
      expect(dropped.map((d) => d.key), [key],
          reason: 'the notification it was given up for is reported');
    });
  });

  group('Given subscriptions whose every listener has cancelled', () {
    const secondKey = '@alice:discover_response_2.$_namespace@alice';

    test(
        'when 100 distinct regexes have each been subscribed and cancelled, '
        'then the service holds as many subscriptions as before them',
        () async {
      final baseline = service.getStreamListenersCount();
      final listeners = [
        for (var i = 0; i < 100; i++)
          service.subscribe(regex: 'conversation_$i\\.').listen((_) {})
      ];
      expect(service.getStreamListenersCount(), baseline + 100,
          reason: 'precondition: a subscription with a listener is held');

      for (final listener in listeners) {
        await listener.cancel();
      }

      expect(service.getStreamListenersCount(), baseline,
          reason: 'a subscription nobody listens to must be released, or one '
              'is held for each distinct regex the client ever subscribed, '
              'and every notification is matched against each');
    });

    test(
        'when a notification arrives that only a cancelled decrypting '
        'subscription matches, then it is not decrypted', () async {
      await service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((_) {})
          .cancel();

      await deliver(_frame(key));

      expect(provider.decrypts, 0,
          reason: 'nobody receives the plaintext, so decrypting it is work '
              'done for a subscriber that has gone');
    });

    test(
        'when a live subscriber\'s notifications wait for their key, then the '
        'cancelled subscription takes no room from them in the park', () async {
      final maxParked = NotificationServiceImpl.maxParked;
      addTearDown(() => NotificationServiceImpl.maxParked = maxParked);
      NotificationServiceImpl.maxParked = 2;
      provider.filed = false;
      final dropped = <DroppedNotification>[];
      service.droppedEvents.listen(dropped.add);
      await service
          .subscribe(regex: r'\.sshrvd@alice', shouldDecrypt: true)
          .listen((_) {})
          .cancel();
      service
          .subscribe(regex: r'discover_response', shouldDecrypt: true)
          .listen((_) {});

      await deliver(_frame(key));
      await deliver(_frame(secondKey));

      expect(dropped, isEmpty,
          reason: 'the park holds two and the live subscriber waits on two; '
              'a share parked for a subscription nobody listens to evicts one '
              'of them, and nothing re-delivers it');
      expect(service.parkedCount, 2);
    });

    test(
        'when a stream subscribe returned for the same regex is listened to '
        'afterwards, then it receives notifications', () async {
      final earlier =
          service.subscribe(regex: r'discover_response', shouldDecrypt: true);
      final later =
          service.subscribe(regex: r'discover_response', shouldDecrypt: true);
      await earlier.listen((_) {}).cancel();

      final seen = <String?>[];
      later.listen((n) => seen.add(n.value));
      await deliver(_frame(key));

      expect(seen, [_plaintext],
          reason: 'the earlier listener leaving must not end a subscription '
              'another caller holds and has yet to listen to');
    });

    test(
        'when the same stream is listened to again, then it receives '
        'notifications', () async {
      final stream =
          service.subscribe(regex: r'discover_response', shouldDecrypt: true);
      await stream.listen((_) {}).cancel();

      final seen = <String?>[];
      stream.listen((n) => seen.add(n.value));
      await deliver(_frame(key));

      expect(seen, [_plaintext],
          reason: 'listening to a released subscription\'s stream again holds '
              'it again');
    });
  });

  group('Given a stream subscribe returned for a regex and decryption', () {
    test(
        'when subscribe is called again with the same arguments, then the '
        'stream it returns compares equal, and one asking for anything else '
        'does not', () {
      final stream =
          service.subscribe(regex: r'discover_response', shouldDecrypt: true);

      expect(
          service.subscribe(regex: r'discover_response', shouldDecrypt: true),
          stream,
          reason: 'a caller that subscribes again on every rebuild must be '
              'able to tell it already holds this stream');
      expect(
          service
              .subscribe(regex: r'discover_response', shouldDecrypt: true)
              .hashCode,
          stream.hashCode);
      expect(
          service.subscribe(regex: r'discover_response', shouldDecrypt: false),
          isNot(stream),
          reason: 'a stream asking for the other decryption is another '
              'subscription');
      expect(service.subscribe(regex: r'discover', shouldDecrypt: true),
          isNot(stream),
          reason: 'a stream asking for another regex is another subscription');
    });

    test(
        'when another client\'s service is asked for the same, then its stream '
        'does not compare equal', () async {
      final other = MockAtClientImpl();
      when(() => other.getCurrentAtSign()).thenReturn('@bob');
      when(() => other.atSign).thenReturn('@bob'.toAtsign());
      when(() => other.getPreferences())
          .thenReturn(AtClientPreference()..namespace = _namespace);
      final otherService = await NotificationServiceImpl.create(other,
              monitor: _FakeMonitor(),
              secondaryAddressFinder: defaultAtDirectory)
          as NotificationServiceImpl;
      addTearDown(otherService.stopAllSubscriptions);

      expect(
          otherService.subscribe(
              regex: r'discover_response', shouldDecrypt: true),
          isNot(service.subscribe(
              regex: r'discover_response', shouldDecrypt: true)),
          reason: 'a subscription is its atSign\'s own; two clients asking '
              'for the same regex hold different things');
    });

    test(
        'when the app subscribes again with the same arguments on a rebuild, '
        'then a notification waiting for its key is still delivered', () async {
      provider.filed = false;
      final delivered = Completer<String?>();
      final droppedOne = Completer<DroppedNotification>();
      service.droppedEvents.listen((d) {
        if (!droppedOne.isCompleted) droppedOne.complete(d);
      });
      void onNotification(AtNotification n) => delivered.complete(n.value);
      var stream =
          service.subscribe(regex: r'discover_response', shouldDecrypt: true);
      var listener = stream.listen(onNotification);
      await deliver(_frame(key));
      expect(service.parkedCount, 1, reason: 'precondition: it parked');

      Future<void> rebuildAsStreamBuilderDoes(
          Stream<AtNotification> given) async {
        if (given == stream) return;
        await listener.cancel();
        stream = given;
        listener = stream.listen(onNotification);
      }

      await rebuildAsStreamBuilderDoes(
          service.subscribe(regex: r'discover_response', shouldDecrypt: true));
      provider.filed = true;
      ring.announce();
      final outcome =
          await Future.any<Object?>([delivered.future, droppedOne.future])
              .timeout(const Duration(seconds: 10));

      expect(outcome, _plaintext,
          reason: 'a caller that subscribes again on every rebuild keeps its '
              'subscription, and what it is waiting to receive');
    });
  });

  group('Given a stream subscribe returned before the service stopped', () {
    test('when it is listened to after the stop, then it ends', () async {
      final stream =
          service.subscribe(regex: r'discover_response', shouldDecrypt: true);
      service.stopAllSubscriptions();

      var ended = false;
      stream.listen((_) {}, onDone: () => ended = true);
      await Future<void>.delayed(Duration.zero);

      expect(ended, isTrue,
          reason: 'a stopped service delivers nothing again, so a stream '
              'listened to after the stop ends rather than waiting forever');
      expect(service.getStreamListenersCount(), 0);
    });
  });

  group('Given a listener paused when the service stops', () {
    test('when the service stops, then it holds no subscription at once', () {
      service.subscribe(regex: r'discover_response').listen((_) {}).pause();
      expect(service.getStreamListenersCount(), 1,
          reason: 'precondition: the paused listener is held');

      service.stopAllSubscriptions();

      expect(service.getStreamListenersCount(), 0,
          reason: 'a stopped service holds no subscription, whether or not '
              'its listener ever takes the end of its stream');
    });
  });

  test(
      'control: a live subscriber alone waits in the park without a drop, '
      'with the same park bound and notifications', () async {
    // NOTE: without this arm, the park test above could be red for a bound
    // the live subscriber overflows alone.
    final maxParked = NotificationServiceImpl.maxParked;
    addTearDown(() => NotificationServiceImpl.maxParked = maxParked);
    NotificationServiceImpl.maxParked = 2;
    provider.filed = false;
    final dropped = <DroppedNotification>[];
    service.droppedEvents.listen(dropped.add);
    service
        .subscribe(regex: r'discover_response', shouldDecrypt: true)
        .listen((_) {});

    await deliver(_frame(key));
    await deliver(_frame('@alice:discover_response_2.$_namespace@alice'));

    expect(dropped, isEmpty);
    expect(service.parkedCount, 2);
  });
}
