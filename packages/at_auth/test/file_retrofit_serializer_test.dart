import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:test/test.dart';

/// [fileRetrofitSerializer] is what a `dart:io` caller assigns to
/// [retrofitSerializer] so two retrofits of one keyfile cannot interleave.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('retrofit_lock'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Runs [n] overlapping actions through [serialize] and returns the order
  /// they entered and left in, e.g. `in0 out0 in1 out1` when serialised and
  /// `in0 in1 out0 out1` when not.
  Future<List<String>> interleavingOf(
      RetrofitSerializer serialize, AtKeysIo keysIo) async {
    final trace = <String>[];
    Future<void> body(int i) => serialize<void>(keysIo, '@alice🛠', () async {
          trace.add('in$i');
          await Future.delayed(const Duration(milliseconds: 60));
          trace.add('out$i');
        });
    await Future.wait([body(0), body(1)]);
    return trace;
  }

  test('a file-backed store runs retrofits one at a time', () async {
    final io = FileAtKeysIo(filePath: (a) => '${tmp.path}/$a.atKeys');
    final trace = await interleavingOf(fileRetrofitSerializer, io);

    // Each action must close before the next opens. Order between them is not
    // pinned - either may win the lock - so this checks the shape, not who.
    expect(trace.length, 4);
    expect(trace[0].startsWith('in'), isTrue);
    expect(trace[1], 'out${trace[0].substring(2)}',
        reason: 'the second retrofit entered before the first left, so the '
            'lock did not hold: $trace');
  }, timeout: Timeout(Duration(seconds: 30)));

  test('an in-memory store runs them concurrently', () async {
    // The control. Without it, the test above would pass just as well against
    // a serialiser that always locks, or one that locks nothing and happens to
    // schedule sequentially - this proves the file case is doing the work.
    final trace =
        await interleavingOf(fileRetrofitSerializer, InMemoryAtKeysIo());

    expect(trace.length, 4);
    expect(trace.sublist(0, 2), ['in0', 'in1'],
        reason: 'a store no other process can open should not be serialised, '
            'but these did not overlap: $trace');
  }, timeout: Timeout(Duration(seconds: 30)));

  test('the lock file is cleaned up', () async {
    final io = FileAtKeysIo(filePath: (a) => '${tmp.path}/$a.atKeys');
    await fileRetrofitSerializer<void>(io, '@alice🛠', () async {});

    final leftovers = tmp
        .listSync()
        .map((e) => e.path.split('/').last)
        .where((n) => n.contains('.lock'))
        .toList();
    expect(leftovers, isEmpty, reason: 'lock left behind: $leftovers');
  });
}
