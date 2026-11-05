import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_server_features.dart';
import 'package:at_client/src/transformer/request_transformer/notify_request_transformer.dart';
import 'package:at_lookup/at_lookup.dart' show OutboundConnection;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';

class _Connection extends Mock implements OutboundConnection {}

/// What a client tells its atServer about a notification's lifetime: an
/// explicit expiry and `eph` where the atServer lists them, else `ttln`.
void main() {
  late MockAtClient client;
  late MockRemoteSecondary remote;
  late int infoAsked;
  late String infoReply;
  late OutboundConnection connection;

  final logs = RecordedLogs();
  setUpAll(() => logs.installOn(level: 'warning'));

  const allFeatures = 'data:{"version":"3.17.0","features":['
      '{"name":"notify.eAtn","status":"GA","description":"x"},'
      '{"name":"notify.eph","status":"GA","description":"x"}]}';

  setUp(() {
    client = MockAtClient();
    remote = MockRemoteSecondary();
    infoAsked = 0;
    infoReply = allFeatures;
    when(() => client.getCurrentAtSign()).thenReturn('@alice');
    when(() => client.getRemoteSecondary()).thenReturn(remote);
    connection = _Connection();
    final lookup = MockAtLookUp();
    when(() => remote.atLookUp).thenReturn(lookup);
    when(() => lookup.connection).thenAnswer((_) => connection);
    when(() => remote.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((inv) async {
      final command = inv.positionalArguments[0] as String;
      if (command != 'info\n') {
        throw StateError('unexpected command: $command');
      }
      infoAsked++;
      return infoReply;
    });
  });

  group('AtServerFeatures', () {
    test('asks once per connection and remembers', () async {
      final features = AtServerFeatures(client);
      expect(await features.has('notify.eph'), isTrue);
      expect(await features.has('notify.eAtn'), isTrue);
      expect(await features.has('notify.unlisted'), isFalse);
      expect(infoAsked, 1);
    });

    test('asks again on a new connection, and only then', () async {
      final features = AtServerFeatures(client);
      await features.has('notify.eph');
      infoReply = 'data:{"version":"3.16.5"}';
      expect(await features.has('notify.eph'), isTrue,
          reason: 'the same connection keeps its answer');
      connection = _Connection();
      expect(await features.has('notify.eph'), isFalse,
          reason: 'a new connection can reach an atServer that restarted');
      expect(infoAsked, 2);
    });

    test('a Retired feature is absent, and any other status is present',
        () async {
      infoReply = 'data:{"version":"3.17.0","features":['
          '{"name":"notify.eph","status":"Retired","description":"x"},'
          '{"name":"notify.eAtn","status":"Deprecated","description":"x"}]}';
      final features = AtServerFeatures(client);
      expect(await features.has('notify.eph'), isFalse);
      expect(await features.has('notify.eAtn'), isTrue,
          reason: 'a Deprecated feature still works');
    });

    test('a feature that is not GA warns once per connection', () async {
      infoReply = 'data:{"version":"3.17.0","features":['
          '{"name":"notify.eph","status":"Beta","description":"x"},'
          '{"name":"notify.eAtn","status":"GA","description":"x"}]}';
      final features = AtServerFeatures(client);
      logs.records.clear();
      await features.has('notify.eph');
      await features.has('notify.eph');
      await features.has('notify.eAtn');
      expect(logs.at('WARNING').where((m) => m.contains('notify.eph')),
          hasLength(1));
      expect(
          logs.at('WARNING').where((m) => m.contains('notify.eAtn')), isEmpty,
          reason: 'the control: a GA feature warns nothing');

      connection = _Connection();
      await features.has('notify.eph');
      expect(logs.at('WARNING').where((m) => m.contains('notify.eph')),
          hasLength(2),
          reason: 'a new connection is a new answer, and warns again');
    });

    test('an answer it cannot read is no features, and is asked again',
        () async {
      infoReply = 'data:not json';
      final features = AtServerFeatures(client);
      expect(await features.has('notify.eph'), isFalse);
      infoReply = allFeatures;
      expect(await features.has('notify.eph'), isTrue,
          reason: 'nothing unreadable is kept');
      expect(infoAsked, 2);
      when(() => remote.executeCommand(any(), auth: any(named: 'auth')))
          .thenThrow(StateError('offline'));
      expect(await AtServerFeatures(client).has('notify.eph'), isFalse);
    });
  });

  group('notify: the transformer writes the lifetime the atServer accepts', () {
    NotificationParams params({bool ephemeral = false, int? ttr}) {
      final atKey = AtKey.fromString('@bob:phone.wavi@alice')
        ..metadata.isEncrypted = false
        ..metadata.ttr = ttr;
      return NotificationParams.forUpdate(atKey,
          value: 'x',
          notificationExpiry: const Duration(minutes: 10),
          ephemeral: ephemeral);
    }

    test('an explicit expiry and eph, clamped to two minutes', () async {
      final before = DateTime.now().toUtc();
      final builder = await NotificationRequestTransformer(client)
          .transform(params(ephemeral: true));
      expect(builder.ephemeral, isTrue);
      expect(builder.ttln, isNull, reason: 'one expiry, never both');
      expect(builder.notificationExpiresAt!.difference(before).inSeconds,
          inInclusiveRange(119, 121));
    });

    test('an ordinary notification keeps its own expiry', () async {
      final before = DateTime.now().toUtc();
      final builder =
          await NotificationRequestTransformer(client).transform(params());
      expect(builder.ephemeral, isFalse);
      expect(builder.notificationExpiresAt!.difference(before).inSeconds,
          inInclusiveRange(599, 601));
    });

    test('ttln and no eph on an atServer that lists neither', () async {
      infoReply = 'data:{"version":"3.16.5"}';
      final builder = await NotificationRequestTransformer(client)
          .transform(params(ephemeral: true));
      expect(builder.ttln, 600000,
          reason: 'not clamped: without eph it is an ordinary notification');
      expect(builder.notificationExpiresAt, isNull);
      expect(builder.ephemeral, isFalse);
    });

    test('eph with a ttr is refused before anything is sent', () async {
      await expectLater(
          NotificationRequestTransformer(client)
              .transform(params(ephemeral: true, ttr: 60000)),
          throwsArgumentError);
      expect(infoAsked, 0,
          reason: 'refused on its own terms, whatever the atServer offers');
    });
  });
}
