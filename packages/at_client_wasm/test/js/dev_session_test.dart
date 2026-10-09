import 'package:at_client/at_client.dart';
import 'package:test/test.dart';
import 'package:test/fake.dart';
import 'package:at_client_wasm/src/js/dev_session.dart';

class _FakeClient extends Fake implements AtClient {
  final Map<String, dynamic> store = {};
  AtKey? lastPutKey;
  var stops = 0;

  @override
  String? getCurrentAtSign() => '@alice';

  @override
  Future<bool> put(AtKey key, dynamic value,
      {bool isDedicated = false, PutRequestOptions? putRequestOptions}) async {
    lastPutKey = key;
    store[key.toString()] = value;
    return true;
  }

  @override
  Future<AtValue> get(AtKey key,
      {bool isDedicated = false, GetRequestOptions? getRequestOptions}) async {
    if (key.key == 'missing') {
      throw KeyNotFoundException('missing');
    }
    if (key.key == 'error') {
      throw StateError('boom');
    }
    return AtValue()..value = store[key.toString()];
  }

  @override
  Future<bool> delete(AtKey key,
      {bool isDedicated = false,
      DeleteRequestOptions? deleteRequestOptions}) async {
    store.remove(key.toString());
    return true;
  }

  @override
  Future<void> stop() async => stops++;
}

void main() {
  group('AtClientDevSession', () {
    test('T7: put constructs correct AtKey', () async {
      final fake = _FakeClient();
      final session = AtClientDevSession(fake, app: 'myapp');

      await session.put('k', 'v');

      final key = fake.lastPutKey!;
      expect(key.key, 'k');
      expect(key.namespace, 'myapp');
      expect(key.sharedBy, '@alice');
      expect(key.sharedWith, isNull);
      expect(key.metadata.isPublic, isFalse);
    });

    test('T8: get handles KeyNotFoundException and propagates others',
        () async {
      final fake = _FakeClient();
      final session = AtClientDevSession(fake, app: 'myapp');

      final missing = await session.get('missing');
      expect(missing, isNull);

      expect(() => session.get('error'), throwsA(isA<StateError>()));
    });

    test('close stops the client once', () async {
      final fake = _FakeClient();
      final session = AtClientDevSession(fake, app: 'myapp');

      await session.close();
      await session.close();

      expect(fake.stops, 1);
    });
  });
}
