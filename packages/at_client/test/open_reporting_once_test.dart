import 'dart:async';
import 'dart:io';

import 'package:at_client/src/storage/hive/open_reporting_once.dart';
import 'package:test/test.dart';

/// [openReportingOnce] runs an open whose failure hive also leaves unhandled,
/// and reports that failure once, to the caller.
void main() {
  /// Runs [body] in a zone standing in for the caller's, and returns every
  /// error left unhandled there once [body] and anything it scheduled are done.
  Future<List<Object>> uncaughtAround(Future<void> Function() body) async {
    final uncaught = <Object>[];
    final done = Completer<void>();
    unawaited(runZonedGuarded(() async {
      await body();
      done.complete();
    }, (e, _) => uncaught.add(e)));
    await done.future;
    await pumpEventQueue();
    return uncaught;
  }

  /// Fails as hive's box open does: the future it parks concurrent openers on
  /// completes with [reported], which nothing listens to, and [thrown] is
  /// what the caller gets.
  Future<Never> failLikeHive(Object reported, Object thrown) async {
    Completer<void>().completeError(reported);
    throw thrown;
  }

  test('a failure the open also leaves unhandled reaches the caller once',
      () async {
    const error = FileSystemException('Cannot open file');
    Object? caught;

    final uncaught = await uncaughtAround(() async {
      try {
        await openReportingOnce(() => failLikeHive(error, error));
      } catch (e) {
        caught = e;
      }
    });

    expect(caught, same(error));
    expect(uncaught, isEmpty);
  });

  test('a failure a store wraps reaches the caller once, as the wrapped error',
      () async {
    const raw = FileSystemException('Cannot open file');
    final wrapped =
        Exception('Exception initializing secondary keystore: $raw');
    Object? caught;

    final uncaught = await uncaughtAround(() async {
      try {
        await openReportingOnce(() => failLikeHive(raw, wrapped));
      } catch (e) {
        caught = e;
      }
    });

    expect(caught, same(wrapped));
    expect(uncaught, isEmpty,
        reason: 'hive reported the raw error, which the wrapped one quotes');
  });

  test('a failure reported before the open throws reaches the caller once',
      () async {
    const error = FileSystemException('Cannot open file');
    Object? caught;

    final uncaught = await uncaughtAround(() async {
      try {
        await openReportingOnce(() async {
          Completer<void>().completeError(error);
          await pumpEventQueue();
          throw error;
        });
      } catch (e) {
        caught = e;
      }
    });

    expect(caught, same(error));
    expect(uncaught, isEmpty);
  });

  test('another error the failed open leaves unhandled reaches the caller zone',
      () async {
    final before = StateError('something else, before the failure');
    final after = StateError('something else, after the failure');
    final blank = _Unnamed();
    Object? caught;

    final uncaught = await uncaughtAround(() async {
      try {
        await openReportingOnce(() async {
          scheduleMicrotask(() => throw before);
          Timer.run(() => throw after);
          Timer.run(() => throw blank);
          await Future<void>.microtask(() {});
          const error = FileSystemException('Cannot open file');
          return failLikeHive(error, error);
        });
      } catch (e) {
        caught = e;
      }
    });

    expect(caught, isA<FileSystemException>());
    expect(uncaught, [same(before), same(after), same(blank)],
        reason: 'only the failure the caller holds is dropped, and an error '
            'with nothing to quote is quoted in nothing');
  });

  test('an error a successful open leaves unhandled reaches the caller zone',
      () async {
    final other = StateError('something else');
    Object? opened;

    final uncaught = await uncaughtAround(() async {
      opened = await openReportingOnce(() async {
        scheduleMicrotask(() => throw other);
        return 'box';
      });
    });

    expect(opened, 'box');
    expect(uncaught, [same(other)]);
  });
}

class _Unnamed {
  @override
  String toString() => '';
}
