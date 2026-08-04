import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_utils/at_logger.dart';

/// Two atSigns' clients, live at the same time.
///
/// **Why this has to exist.** `AtClientManager` is a process-wide singleton and
/// `setCurrentAtSign` stops the outgoing client — which also unsets its
/// `notificationService`. So under the singleton, bringing the second atSign up
/// kills the first atSign's monitor, and a subscription taken before the switch
/// is dead by the time there is anything to send it. That is why the notify
/// **receive** path has never had live coverage in this suite despite both
/// halves being implemented: no test could hold a subscription on one atSign
/// while another sent to it, in either order.
///
/// **The lever** is `AtClientManager`'s public constructor. One manager per
/// atSign, each owning its own client, `notificationService` and `syncService`.
/// Nothing in `AtClientImpl` objects: its instance cache is keyed by atSign, so
/// two *different* atSigns never collide there.
///
/// **The constraint that comes with it, and it is sharp.** That cache is keyed
/// by atSign and nothing else. While a [ConcurrentClients] is open, nothing may
/// call `AtClientManager.getInstance().setCurrentAtSign` for either of its
/// atSigns: doing so hands the *same cached* `AtClientImpl` a freshly built
/// `notificationService`, silently replacing the one this holds a subscription
/// on. The symptom is a subscription that stays open and simply never fires,
/// which reads as "the notification was not sent" — so the failure would be
/// attributed to the code under test rather than to the harness.
class ConcurrentClients {
  static final AtSignLogger _logger = AtSignLogger('ConcurrentClients');

  final AtClient first;
  final AtClient second;

  ConcurrentClients._(this.first, this.second);

  /// Brings [firstAtSign] and [secondAtSign] up together on [namespace].
  ///
  /// Sequential rather than concurrent on purpose: both go through the same
  /// authentication and encryption-key setup, and interleaving two of those
  /// buys nothing while making a failure much harder to attribute.
  static Future<ConcurrentClients> open(
    String firstAtSign,
    String secondAtSign,
    String namespace,
    String authType, {
    bool enableInitialSync = true,
  }) async {
    if (firstAtSign == secondAtSign) {
      throw ArgumentError.value(
          secondAtSign,
          'secondAtSign',
          'must differ from firstAtSign — AtClientImpl caches by atSign, so '
              'one atSign cannot be two concurrently live clients');
    }

    final firstManager = AtClientManager(firstAtSign);
    await TestSuiteInitializer.getInstance().testInitializer(
        firstAtSign, namespace, authType,
        enableInitialSync: enableInitialSync, manager: firstManager);

    final secondManager = AtClientManager(secondAtSign);
    await TestSuiteInitializer.getInstance().testInitializer(
        secondAtSign, namespace, authType,
        enableInitialSync: enableInitialSync, manager: secondManager);

    // Checked rather than assumed. If either client had been torn down by the
    // other coming up, every test built on this would fail somewhere far from
    // the cause — and a monitor test would fail as a silent non-delivery,
    // which looks exactly like the product being broken.
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
