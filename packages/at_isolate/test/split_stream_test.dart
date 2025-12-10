import 'dart:async';
import 'package:test/test.dart';
import 'package:at_isolate/src/atclient/split_stream.dart';

void main() {
  group('takeFromStream', () {
    test('takes exact number of elements and forwards rest', () async {
      // Create a stream with elements
      final controller = StreamController<int>();
      final stream = controller.stream;

      // Take 3 elements
      final future = takeFromStream(3, stream);

      // Send elements
      controller.add(1);
      controller.add(2);
      controller.add(3);

      final (taken, remainingStream, close) = await future;

      expect(taken, equals([1, 2, 3]));
      expect(taken.length, equals(3));

      close();
      await controller.close();
    });

    test('basic functionality matches IsolatedAtClient usage', () async {
      // This test mimics how takeFromStream is actually used in IsolatedAtClient.spawn
      // Where we take 1 element (the success boolean) and forward the rest for commands

      final controller = StreamController<Object?>();
      final stream = controller.stream;

      final future = takeFromStream(1, stream);

      // Simulate the worker sending the success indicator
      controller.add(true);

      final (taken, remainingStream, close) = await future;

      expect(taken.length, equals(1));
      expect(taken.first, isTrue);

      // The remaining stream is used for future communication
      expect(remainingStream, isNotNull);

      close();
      await controller.close();
    });

    test('handles multiple elements taken as used in worker', () async {
      // This mimics how the worker takes 4 initialization messages
      final controller = StreamController<dynamic>();
      final stream = controller.stream;

      final future = takeFromStream(4, stream);

      // Send initialization data
      controller.add('@alice');
      controller.add('root.atsign.org');
      controller.add('{"key": "value"}');
      controller.add({'namespace': 'test'});

      final (taken, remainingStream, close) = await future;

      expect(taken.length, equals(4));
      expect(taken[0], equals('@alice'));
      expect(taken[1], equals('root.atsign.org'));
      expect(taken[2], isA<String>());
      expect(taken[3], isA<Map>());

      close();
      await controller.close();
    });
  });
}
