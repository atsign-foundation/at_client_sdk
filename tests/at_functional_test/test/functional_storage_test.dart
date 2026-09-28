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

  test('closeAll closes every bundle, then names the ones a client still held',
      () async {
    final held = storage.forAtSign('@alice🛠');
    final released = storage.forPrincipal('@alice🛠', 'other');
    await held.attach(_Client());
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
    await expectLater(held.attach(_Client()), throwsStateError,
        reason: 'the bundle was closed before the guard fired');
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
