import 'dart:typed_data';

import 'package:at_client_wasm/at_client_wasm.dart';
import 'package:test/test.dart';

void keyBytesStoreContract(String name, Future<KeyBytesStore> Function() make) {
  group(name, () {
    test('put/get/delete isolated by atSign', () async {
      final store = await make();

      final aliceBytes = Uint8List.fromList([1, 2, 3]);
      final bobBytes = Uint8List.fromList([4, 5, 6]);

      await store.put('@alice', aliceBytes);
      await store.put('@bob', bobBytes);

      final getAlice = await store.get('@alice');
      expect(getAlice, aliceBytes);

      final getBob = await store.get('@bob');
      expect(getBob, bobBytes);

      await store.delete('@alice');
      expect(await store.get('@alice'), isNull);
      expect(await store.get('@bob'), bobBytes);
    });

    test('stored bytes are copies', () async {
      final store = await make();
      final bytes = Uint8List.fromList([1, 2, 3]);

      await store.put('@alice', bytes);
      bytes[0] = 99;

      final stored = await store.get('@alice');
      expect(stored![0], 1);

      stored[1] = 99;
      final storedAgain = await store.get('@alice');
      expect(storedAgain![1], 2);
    });

    test('absent returns null', () async {
      final store = await make();
      expect(await store.get('@nobody'), isNull);
    });
  });
}
