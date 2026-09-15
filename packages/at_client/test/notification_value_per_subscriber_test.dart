import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/transformer/response_transformer/notification_response_transformer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

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

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String value) async {
    decrypts++;
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
        {MessageTypeEnum messageType = MessageTypeEnum.key}) =>
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
    service =
        await NotificationServiceImpl.create(atClient, monitor: _FakeMonitor())
            as NotificationServiceImpl;
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
    // A different regex: subscriptions are keyed by regex, so the same one
    // would hand back the first subscription's stream.
    service
        .subscribe(regex: r'discover_response\.sshrvd')
        .listen((n) => raw.add(n.value));

    await deliver(_frame(key));

    expect(decrypting, [_plaintext]);
    expect(raw, [_ciphertext],
        reason: 'shouldDecrypt: false asks for the value as it arrived, '
            'whatever an earlier subscriber did with its own copy');
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
      'an encrypted text message is matched against its decrypted text, and '
      'decrypted once', () async {
    final byText = <String>[];
    final byOther = <String>[];
    service.subscribe(regex: r'ipaddr').listen((n) => byText.add(n.key));
    service
        .subscribe(regex: r'"port"', shouldDecrypt: true)
        .listen((n) => byOther.add(n.key));

    await deliver(_frame('@alice:$_ciphertext',
        // ignore: deprecated_member_use
        messageType: MessageTypeEnum.text));

    expect(byText, ['@alice:$_plaintext'],
        reason: 'a text message\'s key is its ciphertext, so the regex is '
            'matched against the decrypted text');
    expect(byOther, ['@alice:$_plaintext']);
    expect(provider.decrypts, 1);
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
}
