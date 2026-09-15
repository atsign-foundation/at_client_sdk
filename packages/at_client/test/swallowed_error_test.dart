import 'package:at_client/src/util/swallowed_error.dart';
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import 'test_utils/recorded_logs.dart';

/// Exactly what an unstubbed mocktail member does: answers null where the
/// signature promises a value. The `TypeError` is raised by the return check.
Future<void> answersNull() => null as dynamic;

/// The other half of the same mistake: a decode that answers null, and a
/// caller that indexes what it was handed. This is the shape a fixture
/// answering the wrong content produced - `jsonDecode('ok')` gives null, and
/// `null['data']` reaches `noSuchMethod`.
NoSuchMethodError fromIndexingNull() {
  try {
    dynamic decoded;
    final sink = decoded['data'];
    return StateError('indexing null answered $sink instead of raising')
        as NoSuchMethodError;
  } on NoSuchMethodError catch (e) {
    return e;
  }
}

TypeError fromAnsweringNull() {
  try {
    answersNull();
  } on TypeError catch (e) {
    return e;
  }
  throw StateError('answersNull was supposed to raise a TypeError');
}

void main() {
  final logs = RecordedLogs();
  late AtSignLogger logger;

  setUpAll(() => logs.installOn());

  setUp(() {
    logs.records.clear();
    logger = AtSignLogger('logSwallowed test');
  });

  test('a TypeError is a defect, and says so at SEVERE', () {
    logSwallowed(logger, fromAnsweringNull(), 'the step did not run');

    expect(logs.at('SEVERE'), hasLength(1),
        reason: 'a value of the wrong type reaching the call is a bug here or '
            'in a test double, and at warning it reads as one of the '
            'conditions around it. Saw: ${logs.records}');
    expect(logs.at('SEVERE').single, contains('the step did not run'),
        reason: 'and it still carries what the caller said, including what is '
            'now untrue');
    expect(logs.at('SEVERE').single, contains('names a defect'),
        reason: 'and says which of the two it is, so a reader need not know '
            'that a TypeError is the defect-shaped one');
    expect(logs.at('WARNING'), isEmpty);
  });

  test('an Exception is a condition, and stays at WARNING', () {
    logSwallowed(
        logger, Exception('the socket had already gone'), 'the step failed');

    expect(logs.at('WARNING'), hasLength(1),
        reason: 'the control: a genuine condition must keep its level, or '
            'promoting defects would just move the whole population');
    expect(logs.at('SEVERE'), isEmpty);
  });

  test('a NoSuchMethodError is a defect too, and says which one', () {
    logSwallowed(logger, fromIndexingNull(), 'the private was not filed');

    expect(logs.at('SEVERE'), hasLength(1),
        reason: 'a member invoked on a null receiver is the same mistake as a '
            'value of the wrong type arriving - a null reached a place that '
            'needed a value - so it cannot read as a condition either. '
            'Saw: ${logs.records}');
    expect(logs.at('SEVERE').single, contains('NoSuchMethodError'),
        reason: 'and it names which of the two, because they are found in '
            'different places: one at a call boundary, one at a dereference');
    expect(logs.at('SEVERE').single, contains('the private was not filed'));
    expect(logs.at('WARNING'), isEmpty);
  });

  test('a StateError is a condition too, not a defect', () {
    logSwallowed(logger, StateError('SyncService has not yet been set'),
        'the write was not triggered');

    expect(logs.at('WARNING'), hasLength(1),
        reason: 'StateError IS an Error, so classifying on Error rather than '
            'on the two named types would call this a bug. It is not: this '
            'codebase raises StateError for a store that is not open yet and '
            'a service that is not wired yet, and both pass');
    expect(logs.at('SEVERE'), isEmpty);
  });

  test('a routine path keeps INFO for a condition', () {
    logSwallowed(
        logger, Exception('no answer'), 'the next read miss will ask again',
        routine: true);

    expect(logs.at('INFO'), hasLength(1),
        reason: 'a path that expects to fail often must not be promoted to '
            'warning just for passing through here');
    expect(logs.at('WARNING'), isEmpty);
    expect(logs.at('SEVERE'), isEmpty);
  });

  test('a routine path still reports a defect at SEVERE', () {
    logSwallowed(logger, fromAnsweringNull(), 'the ask did not go out',
        routine: true);

    expect(logs.at('SEVERE'), hasLength(1),
        reason: 'routine describes how often the CONDITION happens, not how '
            'much a bug on that path matters');
    expect(logs.at('INFO'), isEmpty);
  });
}
