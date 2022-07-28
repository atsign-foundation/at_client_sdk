import 'package:test/test.dart';

import 'package:at_client/src/key_stream/collection/iterable_key_stream.dart' as _iterable;
import 'package:at_client/src/key_stream/collection/list_key_stream.dart' as _list;
import 'package:at_client/src/key_stream/collection/map_key_stream.dart' as _map;
import 'package:at_client/src/key_stream/collection/set_key_stream.dart' as _set;

void main() {
  group('A group of castTo tests', () {
    test('IterableKeyStream castTo', () {
      var iter = Iterable<int>.generate(5);
      Iterable<int> res = _iterable.castTo(iter);
      // Test that castTo contains the correct contents
      expect(res.length, 5);
      for (int i = 0; i < 5; i++) {
        expect(res.contains(i), true);
      }
      // Ensure the Object reference is different
      expect(res.hashCode == iter.hashCode, false);
    });

    test('ListKeyStream castTo', () {
      var iter = Iterable<int>.generate(5);
      List<int> res = _list.castTo(iter);
      // Test that castTo contains the correct contents
      for (int i = 0; i < 5; i++) {
        expect(res.contains(i), true);
      }
      // Ensure the Object reference is different
      expect(res.hashCode == iter.hashCode, false);
    });

    test('SetKeyStream castTo', () {
      var iter = Iterable<int>.generate(5);
      Set<int> res = _set.castTo(iter);
      // Test that castTo contains the correct contents
      for (int i = 0; i < 5; i++) {
        expect(res.contains(i), true);
      }
      // Ensure the Object reference is different
      expect(res.hashCode == iter.hashCode, false);
    });

    test('MapKeyStream castTo', () {
      var iter = Iterable<MapEntry<String, int>>.generate(5, (i) => MapEntry(i.toString(), i));
      Map<String, int> res = _map.castTo(iter);
      // Test that castTo contains the correct contents
      for (int i = 0; i < 5; i++) {
        expect(res[i.toString()], i);
      }
      // Ensure the Object reference is different
      expect(res.hashCode == iter.hashCode, false);
    });
  });
}
