import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:test/test.dart';

import '../test_utils/ml_dsa_keyfile.dart';

class _RecordingListener implements AtSignChangeListener {
  final events = <SwitchAtSignEvent>[];

  @override
  void listenToAtSignChange(SwitchAtSignEvent switchAtSignEvent) {
    events.add(switchAtSignEvent);
  }
}

/// `AtClientManager.use`: the manager adopts a client the caller built, and
/// stops nothing, since an owned client is its owner's to stop.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('use_');
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    dir.deleteSync(recursive: true);
  });

  Future<AtClient> build(String atSign) async => buildAtClient(
      atSign: atSign,
      namespace: 'lifecycle',
      preference: AtClientPreference()
        ..rootDomain = InternetAddress.loopbackIPv4.address
        ..rootPort = 1
        ..hiveStoragePath = '${dir.path}/$atSign'
        ..namespace = 'lifecycle',
      atKeysIo: await typedKeyfile(atSign, enrollmentId: 'primary'));

  test('use makes the client current, notifies the listeners, and stops '
      'nothing', () async {
    final manager = AtClientManager('@usefirst');
    final listener = _RecordingListener();
    manager.listenToAtSignChange(listener);
    final first = await build('@usefirst');
    final second = await build('@usesecond');

    manager.use(first);
    expect(manager.atClient, same(first));
    expect(listener.events.map((e) => e.newAtClient), [same(first)]);
    expect(listener.events.single.previousAtClient, isNull);

    manager.use(second);
    expect(manager.atClient, same(second));
    expect(listener.events.last.previousAtClient, same(first));
    expect(listener.events.last.newAtClient, same(second));
    expect(first.isStopped, isFalse,
        reason: 'the caller owns the previous client; the manager only '
            'stopped clients it had built itself');
  });

  test('using the current client again is not a switch', () async {
    final manager = AtClientManager('@usesame');
    final listener = _RecordingListener();
    manager.listenToAtSignChange(listener);
    final client = await build('@usesame');

    manager.use(client);
    manager.use(client);
    expect(listener.events, hasLength(1));
    expect(manager.atClient, same(client));
  });
}
