import 'package:at_client/remote_only.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

class _RecordingLocalRecordStore extends InMemoryLocalRecordStore {
  int closeCount = 0;

  @override
  Future<void> close() async {
    closeCount++;
  }
}

void main() {
  late _RecordingLocalRecordStore localStore;
  late RemoteOnlyAtClientStorage storage;

  setUp(() async {
    localStore = _RecordingLocalRecordStore();
    storage = RemoteOnlyAtClientStorage(
        atSign: '@closeprobe',
        remoteSecondary: MockRemoteSecondary(),
        localRecordStore: localStore);
    await storage.openBackend();
  });

  test('close() closes the injected localRecordStore once', () async {
    await storage.close();

    expect(localStore.closeCount, 1);
  });

  test('closeBackend() closes the injected localRecordStore', () async {
    await storage.closeBackend();

    expect(localStore.closeCount, 1);
  });
}
