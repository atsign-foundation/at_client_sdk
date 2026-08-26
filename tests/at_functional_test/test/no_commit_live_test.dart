// The behaviour, against a real atServer: a write that asks not to be recorded
// leaves the commit log where it was, and one that does not ask moves it.
//
// The unit pins prove the flag reaches the wire. Only this proves the atServer
// acts on it — and the difference matters, because an atServer that does not
// honour the flag accepts the command and records the commit anyway, with
// nothing refused and no error returned. Without the control arm below, a run
// where the flag is silently dropped is indistinguishable from one where it
// worked.
//
// Deliberately untagged: this drives no post-quantum mechanism at all.
library;

import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

void main() async {
  late String currentAtSign;
  final namespace = 'wavi';
  late AtClient atClient;

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atClient = (await TestUtils.initAtClient(currentAtSign, namespace,
        posture: PqPosture.legacy)).atClient;
  });

  /// The atServer's own latest commit id, read fresh over the wire.
  Future<int> serverCommitId() async =>
      await SyncUtil().getLatestServerCommitId(
          atClient.getRemoteSecondary()!, '') ??
      -1;

  Future<int> putAndMeasure({required bool noCommit}) async {
    final key = AtKey()
      ..key = 'nc-${Uuid().v4().hashCode}'
      ..namespace = namespace
      ..sharedBy = currentAtSign;
    final before = await serverCommitId();
    final result = await atClient.put(key, 'a value',
        putRequestOptions: PutRequestOptions()
          ..useRemoteAtServer = true
          ..noCommit = noCommit);
    expect(result, isTrue,
        reason: 'the write itself must succeed either way — a refused write '
            'would make both arms look identical for the wrong reason');
    return await serverCommitId() - before;
  }

  group('a write can ask the atServer not to record it', () {
    test('an ordinary write moves the commit log', () async {
      // The control, and it runs first on purpose: if this does not move, the
      // measurement below means nothing and the instrument is what is broken.
      expect(await putAndMeasure(noCommit: false), greaterThan(0),
          reason: 'an ordinary write records a commit, so the atServer\'s '
              'latest commit id must advance');
    });

    test('a write asking not to be recorded leaves it where it was', () async {
      expect(await putAndMeasure(noCommit: true), 0,
          reason: 'the flag reaches the atServer as ":nc" on the command; if '
              'this arm also advances, the atServer parsed the flag and '
              'ignored it rather than acting on it');
    });
  });
}
