import 'dart:async';

import 'package:at_telemetry/src/exporters/at_telemetry_notification_batch.dart';
import 'package:test/test.dart';

void main() {
  group('AtTelemetryNotificationBatch', () {
    test('counts one record per delivery', () {
      final AtTelemetryNotificationBatch batch = AtTelemetryNotificationBatch(
        'payload',
        <Completer<bool>>[Completer<bool>(), Completer<bool>()],
      );

      expect(batch.payload, 'payload');
      expect(batch.recordCount, 2);
    });

    test('completes every delivery with the outcome', () async {
      final List<Completer<bool>> deliveries = <Completer<bool>>[
        Completer<bool>(),
        Completer<bool>(),
      ];

      AtTelemetryNotificationBatch('', deliveries).complete(true);

      expect(
        await Future.wait(
          deliveries.map((Completer<bool> delivery) => delivery.future),
        ),
        <bool>[true, true],
      );
    });

    test('keeps the first outcome when completed twice', () async {
      final Completer<bool> delivery = Completer<bool>();
      final AtTelemetryNotificationBatch batch =
          AtTelemetryNotificationBatch('', <Completer<bool>>[delivery]);

      batch.complete(false);
      batch.complete(true);

      expect(await delivery.future, isFalse);
    });

    test('skips a delivery that something else already completed', () async {
      final Completer<bool> done = Completer<bool>()..complete(true);
      final Completer<bool> open = Completer<bool>();

      expect(
        () => AtTelemetryNotificationBatch('', <Completer<bool>>[done, open])
            .complete(false),
        returnsNormally,
      );
      expect(await done.future, isTrue);
      expect(await open.future, isFalse);
    });

    test('is not affected by later changes to the deliveries list', () {
      final List<Completer<bool>> deliveries = <Completer<bool>>[
        Completer<bool>(),
      ];
      final AtTelemetryNotificationBatch batch =
          AtTelemetryNotificationBatch('', deliveries);

      deliveries.add(Completer<bool>());

      expect(batch.recordCount, 1);
    });
  });
}
