import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

late AtClient sharedByAtClient;
late AtClient sharedWithAtClient;
late String sharedByAtSign;
late String sharedWithAtSign;
final namespace = TestConstants.namespace;

/// Polls the receiver's local hive, syncing on each iteration, until
/// `isKeyExists(cachedAtKeyStr)` matches [wantedExists] or [timeout]
/// elapses. Returns true if the desired state was observed within
/// the timeout, false otherwise.
///
/// Used in this file to ride the cross-server-notify tail: when the
/// publisher puts (or deletes) a key with TTR, the publisher atServer
/// notifies the receiver atServer to create (or drop) the cached
/// copy. That hop is async — on long-running real atServers it can
/// take several seconds. A single `syncData` call may sample the
/// receiver atServer's commitId before the cross-server notify has
/// landed, in which case `_isInSync` returns true with no pull and
/// the cached entry never reaches local hive.
Future<bool> _pollUntilCachedExistsMatches(
  AtClient client,
  String cachedAtKeyStr,
  bool wantedExists, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    await E2ESyncService.getInstance().syncData(client.syncService);
    final exists =
        (await client.getLocalSecondary()?.keyStore?.exists(cachedAtKeyStr)) ??
            false;
    if (exists == wantedExists) return true;
    if (!DateTime.now().isBefore(deadline)) return false;
    await Future.delayed(Duration(seconds: 1));
  }
}

/// Forces `autoNotify=true` on the publisher (sharedBy) atServer.
/// Defensive: a prior CI run's bypasscache_test may have left
/// `autoNotify=false` persisted on the server (its `finally`-based
/// reset is unreliable on test timeouts). Without auto-notify, a
/// publisher's put-with-TTR doesn't trigger the cross-server notify
/// to the receiver atServer, the receiver's cached entry is never
/// created, and these tests hang forever waiting for it.
Future<void> _ensurePublisherAutoNotifyTrue() async {
  await AtClientManager.getInstance().setCurrentAtSign(sharedByAtSign,
      namespace, TestPreferences.getInstance().getPreference(sharedByAtSign));
  await AtClientManager.getInstance()
      .atClient
      .getRemoteSecondary()!
      .executeCommand('config:set:autoNotify=true\n', auth: true);
}

void main() {
  setUpAll(() async {
    sharedByAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    String authType = ConfigUtil.getYaml()['authType'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedByAtSign, namespace, authType);
    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedWithAtSign, namespace, authType);
    // Initialize sharedWithAtSign
    sharedWithAtClient = (await AtClientManager.getInstance().setCurrentAtSign(
            sharedWithAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign)))
        .atClient;
    // Setting sharedByAtSign atClient instance to context.
    sharedByAtClient = (await AtClientManager.getInstance().setCurrentAtSign(
            sharedByAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(sharedByAtSign)))
        .atClient;
    // Defensive: ensure auto-notify is on for the publisher atServer
    // before any TTR-using test runs.
    await _ensurePublisherAutoNotifyTrue();
  });

  test(
      'A test to verify cached key is deleted in sharedWith secondary when CCD is set to true',
      () async {
    // Create a key with TTR set
    var key = 'deletecachedkey-${Uuid().v4().hashCode}';
    // TTL set to 5 minutes — long enough that the publisher's atServer
    // doesn't expire the key before our 60s polling windows complete.
    // 60s would have the test racing TTL expiry and seeing the cached
    // entry disappear for the wrong reason.
    final atKey =
        (AtKey.shared(key, namespace: namespace, sharedBy: sharedByAtSign)
              ..sharedWith(sharedWithAtSign)
              ..cache(-1, true)
              ..timeToLive(5 * TestConstants.oneMinuteMillis))
            .build();
    sharedByAtClient = (await AtClientManager.getInstance().setCurrentAtSign(
            sharedByAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(sharedByAtSign)))
        .atClient;
    final putResult = await sharedByAtClient.put(atKey, 'dummy_cached_value');
    assert(putResult == true);
    await E2ESyncService.getInstance().syncData(sharedByAtClient.syncService);

    // Switch to sharedWith AtSign and fetch the cached key
    sharedWithAtClient = (await AtClientManager.getInstance().setCurrentAtSign(
            sharedWithAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign)))
        .atClient;
    var cachedAtKey = AtKey()
      ..key = key
      ..sharedWith = sharedWithAtSign
      ..sharedBy = sharedByAtSign
      ..namespace = namespace
      ..metadata = (Metadata()..isCached = true);
    final cachedAtKeyStr = cachedAtKey.toString();

    // Poll for the cached entry to appear in the receiver's local hive.
    // The cross-server notify (publisher atServer -> receiver atServer
    // creating `cached:@<sharedWith>:...@<sharedBy>`) is async and on
    // long-running real atServers can take several seconds.
    final cachedAppeared = await _pollUntilCachedExistsMatches(
        sharedWithAtClient, cachedAtKeyStr, true);
    expect(cachedAppeared, true,
        reason: 'cached key never appeared in receiver local hive within '
            'the propagation window');
    var getResponse = await sharedWithAtClient.get(cachedAtKey);
    expect(getResponse.value, 'dummy_cached_value');

    // Switch back to sharedBy AtSign and delete the key
    sharedByAtClient = (await AtClientManager.getInstance().setCurrentAtSign(
            sharedByAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(sharedByAtSign)))
        .atClient;
    await sharedByAtClient.delete(atKey);
    await E2ESyncService.getInstance().syncData(sharedByAtClient.syncService);

    // Switch to sharedWith AtSign and poll for the CCD-driven removal
    // of the cached entry from local hive. CCD=true means the
    // publisher's delete propagates a delete-the-cache directive to
    // the receiver's atServer; same cross-server-notify tail applies.
    sharedWithAtClient = (await AtClientManager.getInstance().setCurrentAtSign(
            sharedWithAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign)))
        .atClient;
    final cachedRemoved = await _pollUntilCachedExistsMatches(
        sharedWithAtClient, cachedAtKeyStr, false);
    expect(cachedRemoved, true,
        reason: 'cached key was not CCD-removed from receiver local hive '
            'within the propagation window');
  }, timeout: Timeout(Duration(minutes: 2)));

  test(
      'A test to verify cached key is deleted when receiver deletes the cached key in the local',
      () async {
    var key = 'testcachedkey-${Uuid().v4().hashCode}';
    // 5-minute TTL for the same reason as the CCD test above —
    // 60s leaves no margin for our polling deadlines.
    final atKey =
        (AtKey.shared(key, namespace: namespace, sharedBy: sharedByAtSign)
              ..sharedWith(sharedWithAtSign)
              ..cache(-1, true)
              ..timeToLive(5 * TestConstants.oneMinuteMillis))
            .build();
    var value = 'test_cached_value';

    var currentAtClient = (await AtClientManager.getInstance().setCurrentAtSign(
            sharedByAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(sharedByAtSign)))
        .atClient;
    // notifying a key with ttr to shared with atSign
    await currentAtClient.put(atKey, value);
    await E2ESyncService.getInstance().syncData(currentAtClient.syncService);

    var sharedWithAtClient = (await AtClientManager.getInstance()
            .setCurrentAtSign(sharedWithAtSign, namespace,
                TestPreferences.getInstance().getPreference(sharedWithAtSign)))
        .atClient;
    var cachedAtKey = AtKey()
      ..key = key
      ..sharedWith = sharedWithAtSign
      ..sharedBy = sharedByAtSign
      ..namespace = namespace
      ..metadata = (Metadata()..isCached = true);
    final cachedAtKeyStr = cachedAtKey.toString();

    // Poll for the cached entry to appear in the receiver's local hive.
    final cachedAppeared = await _pollUntilCachedExistsMatches(
        sharedWithAtClient, cachedAtKeyStr, true);
    expect(cachedAppeared, true,
        reason: 'cached key never appeared in receiver local hive within '
            'the propagation window');

    // Assert cached key is present in the local storage of the sharedWith atSign
    var getResponse = await sharedWithAtClient.get(cachedAtKey);
    expect(getResponse.value, 'test_cached_value');

    var scanResultBeforeDelete = await sharedWithAtClient
        .getRemoteSecondary()!
        .executeCommand('scan $key\n', auth: true);
    expect(scanResultBeforeDelete!.contains(cachedAtKeyStr), true);
    // Delete the cached key in the local secondary of sharedWith atSign
    var deleteResult = await sharedWithAtClient.delete(cachedAtKey);
    expect(deleteResult, true);

    // Poll for the local-then-server delete to propagate. Local hive
    // empties immediately; the receiver's atServer drops the cached
    // entry once the sync queue's delete entry is pushed and the
    // server processes it. Both should be observable within the poll
    // window.
    final cachedRemovedLocally = await _pollUntilCachedExistsMatches(
        sharedWithAtClient, cachedAtKeyStr, false);
    expect(cachedRemovedLocally, true,
        reason: 'cached key was not removed from receiver local hive after '
            'receiver-initiated delete + sync');

    // Poll the server-side scan too — the sync queue's delete push
    // is async with respect to local completion, and on long-running
    // real atServers the server takes a moment to reflect the delete.
    final serverScanDeadline = DateTime.now().add(Duration(seconds: 30));
    String? scanResultAfterDelete;
    while (true) {
      scanResultAfterDelete = await sharedWithAtClient
          .getRemoteSecondary()!
          .executeCommand('scan $key\n', auth: true);
      if (scanResultAfterDelete != null &&
          !scanResultAfterDelete.contains(cachedAtKeyStr)) {
        break;
      }
      if (!DateTime.now().isBefore(serverScanDeadline)) break;
      await Future.delayed(Duration(seconds: 1));
    }
    expect(scanResultAfterDelete!.contains(cachedAtKeyStr), false);
  }, timeout: Timeout(Duration(minutes: 2)));
}
