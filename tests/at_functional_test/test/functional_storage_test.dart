import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/functional_storage.dart';
import 'package:test/fake.dart';
import 'package:test/test.dart';

class _Client extends Fake implements AtClient {
  @override
  String? getCurrentAtSign() => '@alice🛠';

  @override
  String? get enrollmentId => null;
}

/// The storage a test file borrows, and the guard on handing it back.
void main() {
  late FunctionalStorage storage;

  setUp(() => storage = FunctionalStorage('functional_storage_test',
      backend: FunctionalStorageBackend.memory));

  test(
      'closeAll closes every bundle no client holds, then names the ones a '
      'client still held', () async {
    final held = storage.forAtSign('@alice🛠');
    final released = storage.forPrincipal('@alice🛠', 'other');
    final holder = _Client();
    await held.attach(holder);
    final leaver = _Client();
    await released.attach(leaver);
    await released.detach(leaver);

    await expectLater(
        storage.closeAll(),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('1 running client'))
            .having((e) => e.message, 'message',
                contains((held as AtClientStorageBase).location))
            .having((e) => e.message, 'message',
                isNot(contains((released as AtClientStorageBase).location)))),
        reason: 'a client still holding its storage was never stopped, and a '
            'teardown that closed it silently would leave that client writing '
            'into a closed store');
    expect(held.isHeldBy(holder), isTrue,
        reason: 'a storage a client holds is not closed, so the held bundle '
            'is left open under its client');
    await expectLater(
        released.attach(leaver),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('closed and cannot be reopened'))),
        reason: 'the bundle no client held was closed');
    await held.detach(holder);
    await held.close();
  });

  test(
      'closeAll closes every other bundle while an attach is still in flight, '
      'then names the one it left open', () async {
    final attaching = storage.forAtSign('@alice🛠');
    final released = storage.forPrincipal('@alice🛠', 'other');
    final holder = _Client();
    final attach = attaching.attach(holder);
    expect((attaching as AtClientStorageBase).isAttached, isFalse,
        reason: 'the premise: the attach is still opening the backend');

    await expectLater(
        storage.closeAll(),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('1 running client'))
            .having((e) => e.message, 'message', contains(attaching.location))),
        reason: 'a storage a client is still attaching to is not closed');
    await expectLater(
        released.attach(_Client()),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('closed and cannot be reopened'))),
        reason: 'the refusal stopped no later bundle from closing');
    await attach;
    await attaching.detach(holder);
    await attaching.close();
  });

  test('control: closeAll returns quietly when every client has let go',
      () async {
    final bundle = storage.forAtSign('@alice🛠');
    final client = _Client();
    await bundle.attach(client);
    await bundle.detach(client);

    await storage.closeAll();
  });
}
