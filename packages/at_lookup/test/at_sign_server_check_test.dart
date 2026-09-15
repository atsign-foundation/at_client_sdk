import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLookUp extends Mock implements AtLookUp {}

class _Finder implements SecondaryAddressFinder {
  _Finder(this.answer);

  final FutureOr<SecondaryAddress> Function(String atSign) answer;
  final List<(String, Duration?)> asked = [];

  @override
  Future<SecondaryAddress> findSecondary(String atSign,
      {Duration? timeout}) async {
    asked.add((atSign, timeout));
    return answer(atSign);
  }
}

void main() {
  late _MockLookUp lookUp;
  late _Finder finder;

  void answerLookup(Future<String?> Function() response) =>
      when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
          .thenAnswer((_) => response());

  setUp(() {
    lookUp = _MockLookUp();
    finder = _Finder((_) => SecondaryAddress('alice.example', 1234));
    when(() => lookUp.secondaryAddressFinder).thenReturn(finder);
  });

  test('an atSign the atDirectory has no entry for is not in the directory',
      () async {
    finder = _Finder((_) => throw SecondaryNotFoundException('no entry'));
    when(() => lookUp.secondaryAddressFinder).thenReturn(finder);

    final check = await checkAtSignServer(lookUp, '@alice');

    expect(check.state, AtSignServerState.notInDirectory);
    verifyNever(() => lookUp.executeCommand(any(), auth: any(named: 'auth')));
  });

  test('an atDirectory that cannot be asked is unreachable, with its cause',
      () async {
    final cause = RootServerConnectivityException('refused');
    finder = _Finder((_) => throw cause);
    when(() => lookUp.secondaryAddressFinder).thenReturn(finder);

    final check = await checkAtSignServer(lookUp, '@alice');

    expect(check.state, AtSignServerState.directoryUnreachable);
    expect(check.cause, same(cause));
  });

  test('asks the atServer for the public key over the lookup, unauthenticated',
      () async {
    answerLookup(() async => 'data:MIIBIjANBgkq');

    await checkAtSignServer(lookUp, 'alice');

    // Raw literal: the verb the atServer answers.
    verify(() => lookUp.executeCommand('lookup:publickey@alice\n', auth: false))
        .called(1);
    expect(finder.asked.single.$1, '@alice',
        reason: 'the atSign is looked up with its @, whichever way it came');
  });

  test('a public key means activated', () async {
    answerLookup(() async => 'data:MIIBIjANBgkq');

    expect((await checkAtSignServer(lookUp, '@alice')).state,
        AtSignServerState.activated);
  });

  test('a null public key means not activated', () async {
    answerLookup(() async => 'data:null');

    expect((await checkAtSignServer(lookUp, '@alice')).state,
        AtSignServerState.notActivated);
  });

  test('no public key at all means not activated', () async {
    answerLookup(
        () async => throw AtLookUpException('AT0015', 'key not found'));

    final check = await checkAtSignServer(lookUp, '@alice');

    expect(check.state, AtSignServerState.notActivated);
    expect(check.cause, isNull);
  });

  test('any other failure reaching the atServer is unreachable, with its cause',
      () async {
    final cause = AtLookUpException('AT0014', 'Request timed out');
    answerLookup(() async => throw cause);

    final check = await checkAtSignServer(lookUp, '@alice');

    expect(check.state, AtSignServerState.atServerUnreachable);
    expect(check.cause, same(cause));
  });

  test('a connection that fails outright is unreachable too', () async {
    answerLookup(() async => throw SecondaryConnectException('reset'));

    expect((await checkAtSignServer(lookUp, '@alice')).state,
        AtSignServerState.atServerUnreachable);
  });

  test('the timeout bounds both steps', () async {
    const timeout = Duration(milliseconds: 20);
    answerLookup(() => Completer<String?>().future);

    final check = await checkAtSignServer(lookUp, '@alice', timeout: timeout);

    expect(finder.asked.single.$2, timeout,
        reason: 'the atDirectory step is handed the bound');
    expect(check.state, AtSignServerState.atServerUnreachable);
    expect(check.cause, isA<TimeoutException>(),
        reason: 'an atServer that never answers is cut off at the bound');
  });
}
