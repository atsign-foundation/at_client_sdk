import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

const _owner = '@alice';
const _namespace = 'wavi';

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

/// Opens anything, so a record is withheld only by the rule under test and
/// never by a decryption that failed.
class _OpeningProvider extends CryptoProvider {
  @override
  final String id = 'opening-provider';

  @override
  Future<String> decrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      'opened:$value';

  @override
  Future<String> encrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      value;
}

String _frame(String key) => 'notification: ${jsonEncode({
          'id': 'n-${key.hashCode}',
          'key': key,
          'from': '@bob',
          'to': _owner,
          'epochMillis': DateTime.now().millisecondsSinceEpoch,
          'value': 'sealed',
          'operation': 'update',
          'messageType': MessageTypeEnum.key.toString(),
          AtConstants.isEncrypted: true,
          'metadata': {
            AtConstants.appMetadata: Metadata.encodeAppMetadata(
                AppMetadata(providerId: 'opening-provider')),
          },
        })}\n';

/// Conveyance records are the SDK's own: an application sees none unless it
/// asks for hidden keys, and never as a notification.
void main() {
  setUpAll(() {
    registerFallbackValue(FakeAtKey());
    registerFallbackValue(ScanVerbBuilder());
  });

  group('notifications', () {
    late NotificationServiceImpl service;

    setUp(() async {
      final atClient = MockAtClientImpl();
      final provider = _OpeningProvider();
      when(() => atClient.getCurrentAtSign()).thenReturn(_owner);
      when(() => atClient.atSign).thenReturn(_owner.toAtsign());
      when(() => atClient.getPreferences()).thenReturn(AtClientPreference()
        ..namespace = _namespace
        ..crypto = CryptoConfig(
            defaultProviderId: provider.id, providers: [provider]));
      when(() => atClient.put(any(), any(),
              putRequestOptions: any(named: 'putRequestOptions')))
          .thenAnswer((_) async => true);
      service = await NotificationServiceImpl.create(atClient,
          monitor: _FakeMonitor()) as NotificationServiceImpl;
    });

    tearDown(() => service.stopAllSubscriptions());

    test('no subscriber hears a conveyance, whatever its regex', () async {
      final everything = <String>[];
      final opened = <String>[];
      final conveyancesAskedFor = <String>[];
      service.subscribe().listen((n) => everything.add(n.key));
      service.subscribe(shouldDecrypt: true).listen((n) => opened.add(n.key));
      service
          .subscribe(regex: r'__ck')
          .listen((n) => conveyancesAskedFor.add(n.key));

      for (final key in [
        '@alice:ck0000000000001.__ck.$_namespace@bob',
        'cached:@alice:ck0000000000002.__ck.$_namespace@bob',
        '@alice:treaty.$_namespace@bob',
      ]) {
        await service.handleNotificationReceipt(_frame(key));
      }
      await Future<void>.delayed(Duration.zero);

      expect(everything, ['@alice:treaty.$_namespace@bob'],
          reason: 'the control is the value arriving; the conveyances are '
              'the SDK\'s, and a subscriber handed one with shouldDecrypt '
              'gets a content key in plain text');
      expect(opened, ['@alice:treaty.$_namespace@bob']);
      expect(conveyancesAskedFor, isEmpty,
          reason: 'a regex naming them does not reach them');
    });
  });

  group('scans', () {
    late Directory storage;
    late AtClient client;

    setUp(() async {
      storage = await Directory.systemTemp.createTemp('conveyance_hiding');
      final remote = MockRemoteSecondary();
      when(() => remote.executeVerb(any(), sync: any(named: 'sync')))
          .thenAnswer(
              (inv) async => inv.positionalArguments[0] is ScanVerbBuilder
                  ? 'data:${jsonEncode([
                          'phone.$_namespace$_owner',
                          'ck0000000000001.__ck.$_namespace$_owner',
                          '@bob:ck0000000000001.__ck.$_namespace$_owner',
                          'cached:$_owner:ck0000000000002.__ck.$_namespace@bob',
                        ])}'
                  : throw AtKeyNotFoundException('nothing else is stored'));
      client = await AtClientImpl.create(
        _owner,
        _namespace,
        AtClientPreference(posture: PqPosture.legacy)
          ..hiveStoragePath = '${storage.path}/hive'
          ..commitLogPath = '${storage.path}/commit',
        remoteSecondary: remote,
      );
    });

    tearDown(() async {
      for (final c
          in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
        await c.stop();
      }
      await storage.delete(recursive: true);
    });

    test('lists no conveyance record', () async {
      expect(await client.getKeys(useRemoteAtServer: true),
          ['phone.$_namespace$_owner']);
      expect(
          (await client.getAtKeys(useRemoteAtServer: true))
              .map((k) => k.toString()),
          ['phone.$_namespace$_owner']);
    });

    test('lists them when it asks for hidden keys', () async {
      expect(
          await client.getKeys(useRemoteAtServer: true, showHiddenKeys: true),
          hasLength(4));
    });
  });
}
