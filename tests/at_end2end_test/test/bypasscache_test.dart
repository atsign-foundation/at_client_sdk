import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() async {
  late String sharedByAtSign;
  late String sharedWithAtSign;
  final namespace = TestConstants.namespace;
  var uuid = Uuid();
  setUpAll(() async {
    sharedByAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    String authType = ConfigUtil.getYaml()['authType'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedByAtSign, namespace, authType,
            posture: PqPosture.legacy);
    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedWithAtSign, namespace, authType,
            posture: PqPosture.legacy);
  });

  Future<void> setAtSignOneAutoNotify(bool autoNotify) async {
    //  reset the autoNotify to true
    await AtClientManager.getInstance().setCurrentAtSign(sharedByAtSign,
        namespace, TestPreferences.getInstance().getPreference(sharedByAtSign,
            posture: PqPosture.legacy));

    var configResult = await AtClientManager.getInstance()
        .atClient
        .getRemoteSecondary()!
        .executeCommand('config:set:autoNotify=$autoNotify\n', auth: true);
    if (configResult == null) {
      fail('failed to set auto config to $autoNotify');
    }
    expect(configResult.contains('data:ok'), true);
  }

  /// The purpose of this test is to verify the following:
  /// 1. Share a key from sharedByAtSign to sharedWithAtSign with ttr, with autoNotify:true
  /// 2. Perform lookup from sharedWithAtSign  and assert on value - initial value should be returned.
  /// 3. Set the autoNotify to false using the config verb
  /// 4. Update the existing key to a new value
  /// 4. lookup with bypass_cache set to true should return the updated value
  /// 5. lookup with bypass_cache set to false should return the old value
  test('A test to verify bypassCache', () async {
    int uniqueId = uuid.v4().hashCode;
    String keyEntity = 'test_bypass_cached_key-$uniqueId';
    String initialValue = 'initial_value-$uniqueId';
    String updatedValue = 'updated_value-$uniqueId';

    // Use a long TTL (5 minutes) — the test does a put on the
    // publisher, then later does a bypassCache=true lookup that
    // proxies back to the publisher. With our polling deadline of
    // 60s plus the surrounding setCurrentAtSign / sync hops, the
    // total test run can exceed 60s; a 60s TTL would have the
    // publisher's atServer expire the key before the bypassCache
    // lookup arrives, causing
    // `remoteLookUp: remote atServer returned String value 'null'`.
    final AtKey testByPassCacheAtKey = AtKey()
      ..key = keyEntity
      ..sharedWith = sharedWithAtSign
      ..namespace = namespace
      ..sharedBy = sharedByAtSign
      ..metadata = (Metadata()
        ..ttr = 1000
        ..ttl = 5 * TestConstants.oneMinuteMillis);

    // CRITICAL: register the autoNotify=true reset via addTearDown so
    // it runs even if this test times out. A `finally` block won't
    // reliably run when the dart test framework cancels the test
    // future on timeout — leaving `autoNotify=false` persisted on the
    // sharedBy atServer for the next CI run, which then breaks every
    // downstream test that depends on auto-notify firing the cross-
    // server cache notify (deletion_key CCD, sharing_key TTR).
    addTearDown(() async {
      try {
        await setAtSignOneAutoNotify(true);
      } catch (e) {
        // Best-effort; the next test (or the next run's setUp) will
        // re-attempt if needed.
      }
    });

    // Ensure autoNotify is set to true to begin with
    await setAtSignOneAutoNotify(true);

    // Set sharedBy atSign as currentAtSign and Put the initial value
    await AtClientManager.getInstance().setCurrentAtSign(sharedByAtSign,
        namespace, TestPreferences.getInstance().getPreference(sharedByAtSign,
            posture: PqPosture.legacy));

    // Per-key gate: register the listener BEFORE the put so the
    // push event for this key can't fire before the listener is in
    // place. `put` internally calls `syncService.sync()` after
    // enqueueing, which can run to completion (and emit its
    // SyncProgress event) before any subsequent line of test code
    // runs — registering the listener after the put would miss
    // that event and the gate would hang until timeout.
    // `awaitKeyPushed` runs its registration synchronously before
    // returning its Future, so capturing it here is sufficient.
    var pushedInitialValue = E2ESyncService.getInstance().awaitKeyPushed(
        AtClientManager.getInstance().atClient.syncService,
        testByPassCacheAtKey);
    var putResult = await AtClientManager.getInstance()
        .atClient
        .put(testByPassCacheAtKey, initialValue);
    expect(putResult, true);
    await pushedInitialValue;

    // Cross-server propagation: publisher's atServer auto-notifies
    // the receiver's atServer (autoNotify=true at this point). That
    // path is separate from the at_client sync queue we just gated,
    // so still wait for it.
    await Future.delayed(Duration(seconds: 5));

    // Switch to sharedWithAtSign
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign,
        namespace,
        TestPreferences.getInstance().getPreference(sharedWithAtSign,
            posture: PqPosture.legacy));

    await E2ESyncService.getInstance()
        .syncData(AtClientManager.getInstance().atClient.syncService);

    var getKey = AtKey()
      ..key = keyEntity
      ..sharedBy = sharedByAtSign;
    var getResult = await AtClientManager.getInstance().atClient.get(getKey);
    expect(getResult.value, initialValue);
    // Since the put request has a ttr in metadata, a cached key will be created.
    // When a cached key is available, value will be fetched from a cached key.
    // Hence isCached should be true.
    expect(getResult.metadata!.isCached, true);

    // Switch back to sharedByAtSign to update the value of the key.
    await AtClientManager.getInstance().setCurrentAtSign(sharedByAtSign,
        namespace, TestPreferences.getInstance().getPreference(sharedByAtSign,
            posture: PqPosture.legacy));

    // Set autoNotify to false so that the update doesn't propagate to sharedWith AtSign automatically
    await setAtSignOneAutoNotify(false);

    // Per-key gate: register the listener BEFORE the put (see
    // explanation at the initialValue gate above) — `put` may
    // trigger sync to completion before any subsequent line runs,
    // so post-put registration races the very event we're trying
    // to observe.
    //
    // This gate is the primary fix for the historical flake — the
    // prior `syncData` gate could return on an unrelated prior
    // sync event's commit-id match, leaving N+2 still queued; the
    // receiver-side bypassCache lookup then polled for 60s against
    // a publisher atServer that still held `initialValue`.
    var pushedUpdatedValue = E2ESyncService.getInstance().awaitKeyPushed(
        AtClientManager.getInstance().atClient.syncService,
        testByPassCacheAtKey);
    var newPutResult = await AtClientManager.getInstance()
        .atClient
        .put(testByPassCacheAtKey, updatedValue);
    expect(newPutResult, true);
    await pushedUpdatedValue;

    // As atSignTwo
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign,
        namespace,
        TestPreferences.getInstance().getPreference(sharedWithAtSign,
            posture: PqPosture.legacy));

    // Sync - after this we still should have the old value
    await E2ESyncService.getInstance()
        .syncData(AtClientManager.getInstance().atClient.syncService);

    // Get result with bypassCache set to false
    // Since bypassCache is set to false, the value from the returned from the
    // cached key. So the initial value should be returned.
    getKey = AtKey()
      ..key = keyEntity
      ..sharedBy = sharedByAtSign;
    getResult = await AtClientManager.getInstance().atClient.get(getKey,
        getRequestOptions: GetRequestOptions()..bypassCache = false);
    expect(getResult.value, initialValue);
    expect(getResult.metadata!.isCached, true);

    // Get result with bypassCache set to true
    // Since bypassCache is set to true, a lookup should be performed to the
    // sharedBy AtSign and updated value should be fetched.
    // syncData on sharedBy returning success confirms the SDK acked
    // the put, but on long-running real atServers there can be tail
    // latency between the publisher's atServer committing the value
    // and that value being readable via the receiver atServer's
    // outbound `lookup:` (the path bypassCache=true takes). Poll the
    // lookup until we observe updatedValue, with a generous timeout,
    // so this test isn't flaky on cross-server propagation tail.
    getKey = AtKey()
      ..key = keyEntity
      ..sharedBy = sharedByAtSign;
    final pollDeadline = DateTime.now().add(Duration(seconds: 60));
    while (true) {
      getResult = await AtClientManager.getInstance().atClient.get(getKey,
          getRequestOptions: GetRequestOptions()..bypassCache = true);
      if (getResult.value == updatedValue) break;
      if (!DateTime.now().isBefore(pollDeadline)) break;
      await Future.delayed(Duration(seconds: 1));
    }
    expect(getResult.value, updatedValue);
    expect(getResult.metadata!.isCached, false);
    // Sync - after this we should now have the new value
    await E2ESyncService.getInstance()
        .syncData(AtClientManager.getInstance().atClient.syncService);

    // Get Result with byPassCache set to false again
    // should also now return the new value, since cached value will have been updated with the
    // results of the remote lookup, and the cached value will have been synced to the client
    getKey = AtKey()
      ..key = keyEntity
      ..sharedBy = sharedByAtSign;
    var getResultWithFalse = await AtClientManager.getInstance().atClient.get(
        getKey,
        getRequestOptions: GetRequestOptions()..bypassCache = false);
    expect(getResultWithFalse.value, updatedValue);
    expect(getResultWithFalse.metadata!.isCached, true);
  }, timeout: Timeout(Duration(minutes: 3)));
}
