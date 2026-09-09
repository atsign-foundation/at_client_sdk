import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_utils/at_logger.dart';

/// Two atSigns' clients, live at the same time.
///
/// One `AtClientManager` per atSign — the public constructor, not the
/// singleton — each owning its own client, `notificationService` and
/// `syncService`. Under the singleton, `setCurrentAtSign` stops the outgoing
/// client and unsets its `notificationService`, so a subscription taken before
/// a switch is dead by the time there is anything to send it.
///
/// ⚠️ While a [ConcurrentClients] is open, nothing may call
/// `AtClientManager.getInstance().setCurrentAtSign` for either of its atSigns:
/// `AtClientImpl`'s instance cache is keyed by atSign and nothing else, so the
/// call hands the *same cached* client a freshly built `notificationService`,
/// silently replacing the one this holds a subscription on. The symptom is a
/// subscription that stays open and never fires, which reads as "the
/// notification was not sent".
class ConcurrentClients {
  static final AtSignLogger _logger = AtSignLogger('ConcurrentClients');

  final AtClient first;
  final AtClient second;

  ConcurrentClients._(this.first, this.second);

  /// Brings [firstAtSign] and [secondAtSign] up together on [namespace].
  ///
  /// Both come up at [posture]: a pair at different eras is a compatibility
  /// test rather than the concurrency fixture this is, and is written as two
  /// explicit initialisations instead.
  static Future<ConcurrentClients> open(
    String firstAtSign,
    String secondAtSign,
    String namespace,
    String authType, {
    required PqPosture posture,
    bool enableInitialSync = true,
  }) async {
    if (firstAtSign == secondAtSign) {
      throw ArgumentError.value(
          secondAtSign,
          'secondAtSign',
          'must differ from firstAtSign — AtClientImpl caches by '
              '(atSign, enrollmentId), and these clients carry no enrollment '
              'id, so one atSign here cannot be two concurrently live '
              'clients. Two ENROLLMENTS of one atSign can: see '
              'enrolled_client.dart');
    }

    final firstManager = AtClientManager(firstAtSign);
    await TestSuiteInitializer.getInstance().testInitializer(
        firstAtSign, namespace, authType,
        posture: posture,
        enableInitialSync: enableInitialSync,
        manager: firstManager);

    final secondManager = AtClientManager(secondAtSign);
    await TestSuiteInitializer.getInstance().testInitializer(
        secondAtSign, namespace, authType,
        posture: posture,
        enableInitialSync: enableInitialSync,
        manager: secondManager);

    final first = firstManager.atClient;
    final second = secondManager.atClient;
    if (first.isStopped || second.isStopped) {
      throw StateError(
          'Bringing up $secondAtSign stopped a client: $firstAtSign stopped='
          '${first.isStopped}, $secondAtSign stopped=${second.isStopped}. '
          'Two managers should not share teardown — something reintroduced '
          'the singleton path.');
    }
    _logger.info('$firstAtSign and $secondAtSign are both live');
    return ConcurrentClients._(first, second);
  }

  /// Stops both clients. Their monitors go with them.
  Future<void> close() async {
    await first.stop();
    await second.stop();
  }
}
