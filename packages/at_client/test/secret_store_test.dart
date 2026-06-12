import 'package:at_client/src/secret_sharing/secret_store.dart';
import 'package:test/test.dart';

class InMemoryPersistence implements SecretStorePersistence {
  List<Secret> stored = [];
  int saveCount = 0;

  @override
  Future<List<Secret>> load() async => stored;

  @override
  Future<void> save(List<Secret> secrets) async {
    stored = secrets;
    saveCount++;
  }
}

void main() {
  group('SecretStore CRUD', () {
    test('put, get, list, remove', () async {
      final store = SecretStore();
      await store
          .putSecret(Secret(namespace: 'myapp', name: 'token', value: 't1'));
      await store
          .putSecret(Secret(namespace: 'myapp', name: 'pin', value: 'p1'));
      await store
          .putSecret(Secret(namespace: 'mychat', name: 'token', value: 't2'));

      expect(store.getSecret('myapp', 'token')!.value, 't1');
      expect(store.getSecret('mychat', 'token')!.value, 't2');
      expect(store.getSecret('myapp', 'nope'), isNull);

      // (namespace, name) is the identity: same name in two namespaces
      // coexist
      expect(store.listSecrets(), hasLength(3));
      expect(store.listSecrets(namespace: 'myapp'), hasLength(2));

      expect(await store.removeSecret('myapp', 'token'), isTrue);
      expect(await store.removeSecret('myapp', 'token'), isFalse);
      expect(store.listSecrets(), hasLength(2));
    });

    test('putSecret overwrites; putIfNewer only stores strictly newer',
        () async {
      final store = SecretStore();
      final older = Secret(
          namespace: 'myapp',
          name: 'token',
          value: 'old',
          createdAt: DateTime.utc(2026, 1, 1));
      final newer = Secret(
          namespace: 'myapp',
          name: 'token',
          value: 'new',
          createdAt: DateTime.utc(2026, 6, 1));

      await store.putSecret(newer);
      expect(await store.putIfNewer(older), isFalse);
      expect(store.getSecret('myapp', 'token')!.value, 'new');
      // equal createdAt is not newer
      expect(await store.putIfNewer(newer), isFalse);

      await store.putSecret(older); // unconditional overwrite
      expect(store.getSecret('myapp', 'token')!.value, 'old');
      expect(await store.putIfNewer(newer), isTrue);
      expect(store.getSecret('myapp', 'token')!.value, 'new');
    });
  });

  group('reserved names', () {
    test('putSecret rejects __ names unless allowReservedName', () async {
      final store = SecretStore();
      expect(
          () => store.putSecret(
              Secret(namespace: 'myapp', name: '__rk.current', value: 'x')),
          throwsA(isA<ArgumentError>()));
      expect(store.getSecret('myapp', '__rk.current'), isNull);

      await store.putSecret(
          Secret(namespace: 'myapp', name: '__rk.current', value: 'x'),
          allowReservedName: true);
      expect(store.getSecret('myapp', '__rk.current')!.value, 'x');
    });

    test('putIfNewer (the arrival path) accepts reserved names', () async {
      final store = SecretStore();
      expect(
          await store.putIfNewer(
              Secret(namespace: 'myapp', name: '__rk.current', value: 'x')),
          isTrue);
      expect(store.getSecret('myapp', '__rk.current')!.value, 'x');
    });
  });

  group('persistence delegate', () {
    test('mutations save, init loads', () async {
      final persistence = InMemoryPersistence();
      final store = SecretStore(persistence: persistence);
      await store
          .putSecret(Secret(namespace: 'myapp', name: 'token', value: 't1'));
      await store.removeSecret('myapp', 'token');
      await store
          .putSecret(Secret(namespace: 'myapp', name: 'pin', value: 'p1'));
      expect(persistence.saveCount, 3);
      expect(persistence.stored, hasLength(1));

      final reloaded = SecretStore(persistence: persistence);
      await reloaded.init();
      expect(reloaded.getSecret('myapp', 'pin')!.value, 'p1');
    });
  });

  group('namespaceAuthorizes (mirrors the atServer suffix rule)', () {
    test('exact, suffix, wildcard, and non-matches', () {
      expect(SecretStore.namespaceAuthorizes({'myapp': 'rw'}, 'myapp'), isTrue);
      expect(SecretStore.namespaceAuthorizes({'myapp': 'r'}, 'data.myapp'),
          isTrue);
      expect(SecretStore.namespaceAuthorizes({'*': 'rw'}, 'anything'), isTrue);
      // 'mychat' is not authorized by 'myapp', and substring != dot-suffix
      expect(
          SecretStore.namespaceAuthorizes({'myapp': 'rw'}, 'mychat'), isFalse);
      expect(SecretStore.namespaceAuthorizes({'app': 'rw'}, 'myapp'), isFalse);
      expect(SecretStore.namespaceAuthorizes({}, 'myapp'), isFalse);
    });
  });

  group('Secret json', () {
    test('round trip and malformed', () {
      final secret = Secret(
          namespace: 'myapp',
          name: 'token',
          value: 't1',
          createdAt: DateTime.utc(2026, 6, 11));
      final reparsed = Secret.fromJson(secret.toJson());
      expect(reparsed.namespace, 'myapp');
      expect(reparsed.name, 'token');
      expect(reparsed.value, 't1');
      expect(reparsed.createdAt, DateTime.utc(2026, 6, 11));

      expect(() => Secret.fromJson({'name': 'x'}),
          throwsA(isA<FormatException>()));
    });
  });
}
