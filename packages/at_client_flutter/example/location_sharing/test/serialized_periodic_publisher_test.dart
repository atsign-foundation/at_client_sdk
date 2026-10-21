import 'dart:async';

import 'package:location_sharing/services/serialized_periodic_publisher.dart';
import 'package:test/test.dart';

void main() {
  test('a tick that arrives mid-publish is skipped, not queued', () async {
    final published = <int>[];
    var fetchCount = 0;
    final firstPublishStarted = Completer<void>();
    final releaseFirstPublish = Completer<void>();

    final publisher = SerializedPeriodicPublisher<int>(
      fetch: () async => ++fetchCount,
      publish: (value) async {
        if (value == 1) {
          firstPublishStarted.complete();
          await releaseFirstPublish.future;
        }
        published.add(value);
      },
    );

    final firstTick = publisher.tick();
    await firstPublishStarted.future;

    // A second tick fires while the first publish is still in flight.
    await publisher.tick();
    expect(fetchCount, 1, reason: 'the in-flight tick must not be fetched for');

    releaseFirstPublish.complete();
    await firstTick;

    expect(published, [1]);
  });

  test('publishes never land out of order across many ticks', () async {
    final published = <int>[];
    var fetchCount = 0;
    final random = [40, 5, 20, 1, 15];

    final publisher = SerializedPeriodicPublisher<int>(
      fetch: () async => ++fetchCount,
      publish: (value) async {
        // Simulate variable publish latency: an earlier tick can take
        // longer than a later one, so without serialising, a late-firing
        // tick for a smaller value could finish first.
        final delayMs = random[(value - 1) % random.length];
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        published.add(value);
      },
    );

    // Fire ticks back-to-back, as a fast Timer.periodic would.
    final ticks = [for (var i = 0; i < 5; i++) publisher.tick()];
    for (final tick in ticks) {
      await tick;
    }

    // Every value that was actually published landed in increasing order
    // (some ticks are legitimately skipped because they land while the
    // previous one is still running).
    for (var i = 1; i < published.length; i++) {
      expect(published[i], greaterThan(published[i - 1]));
    }
  });

  test('tick is a no-op once a previous tick has finished', () async {
    var publishCount = 0;
    final publisher = SerializedPeriodicPublisher<int>(
      fetch: () async => 1,
      publish: (_) async => publishCount++,
    );

    await publisher.tick();
    await publisher.tick();

    expect(publishCount, 2);
  });

  test('a null fetch result is not published', () async {
    var publishCount = 0;
    final publisher = SerializedPeriodicPublisher<int>(
      fetch: () async => null,
      publish: (_) async => publishCount++,
    );

    await publisher.tick();

    expect(publishCount, 0);
  });
}
