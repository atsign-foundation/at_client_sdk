// Test-only helpers for the AtCollection<T> surface. NOT FOR
// PRODUCTION USE. Tests reach private SDK state through the
// `part of 'collections.dart';` directive below — this is the only
// way to drive notifications, clear the static factory registry,
// or build a collection wired to an injected notification stream
// without exporting those entry points on the public AtCollection
// API and bleeding them into consumer auto-complete.
//
// Tests `import 'package:at_client/src/collections/collections_test_hooks.dart';`
// directly — the file is intentionally NOT exported from
// `at_client.dart`. The top-level functions below all carry the
// `@visibleForTesting` annotation so production callers that
// happen to import it still see an analyzer warning.

part of 'collections.dart';

/// Constant for the read-receipt sub-collection's reserved namespace
/// part. Tests assert against this when constructing expected envelope
/// keys.
@visibleForTesting
const String readReceiptNamespacePart = '__rr';

/// Constructs an [AtCollection<T>] with an injected notification
/// stream — required so tests drive notification events without an
/// active server connection. Callers supply [notifications] (typically
/// a `StreamController.broadcast()` they own); the produced collection
/// subscribes to it as if it were the live monitor stream.
@visibleForTesting
AtCollection<T> collectionWithInjectedNotifications<T>(
  AtClient atClient,
  String namespace,
  Duration defaultExpiration, {
  required Stream<AtNotification> notifications,
  T Function(Map<String, dynamic>)? fromJson,
  String? typeTag,
}) =>
    AtCollection<T>._withInjectedNotifications(
      atClient,
      namespace,
      defaultExpiration,
      notifications: notifications,
      fromJson: fromJson,
      typeTag: typeTag,
    );

/// Constructs a sub-collection of [parent] with an injected
/// notification stream. Same semantics as
/// [collectionWithInjectedNotifications] but for nested collections.
@visibleForTesting
AtCollection<U> subCollectionWithInjectedNotifications<T, U>(
  AtCollection<T> parent, {
  required CItem<T> parentItem,
  required String subName,
  required Duration defaultExpiration,
  required Stream<AtNotification> notifications,
  U Function(Map<String, dynamic>)? fromJson,
  String? typeTag,
}) =>
    parent._subCollectionWithInjectedNotifications<U>(
      parent: parentItem,
      subName: subName,
      defaultExpiration: defaultExpiration,
      notifications: notifications,
      fromJson: fromJson,
      typeTag: typeTag,
    );

/// Constructs an [AtCollection<T>] with an injected [DataEvent]
/// stream — the data-events analogue of
/// [collectionWithInjectedNotifications]. Lets tests drive the
/// `eventsFromLocalSecondary: true` path without a live LocalSecondary
/// stream subscription.
@visibleForTesting
AtCollection<T> collectionWithInjectedDataEvents<T>(
  AtClient atClient,
  String namespace,
  Duration defaultExpiration, {
  required Stream<DataEvent> dataEvents,
  T Function(Map<String, dynamic>)? fromJson,
  String? typeTag,
}) =>
    AtCollection<T>._withInjectedDataEvents(
      atClient,
      namespace,
      defaultExpiration,
      dataEvents: dataEvents,
      fromJson: fromJson,
      typeTag: typeTag,
    );

/// Routes [n] through [coll]'s top-level notification handler — the
/// same entry point the live monitor subscription uses.
@visibleForTesting
Future<void> handleNotificationForTest(
  AtCollection<dynamic> coll,
  AtNotification n,
) =>
    coll._handleNotificationImpl(n);

/// Routes [event] through [coll]'s data-event handler — the same entry
/// point the live LocalSecondary subscription uses on the
/// `eventsFromLocalSecondary: true` path.
@visibleForTesting
Future<void> handleDataEventForTest(
  AtCollection<dynamic> coll,
  DataEvent event,
) =>
    coll._handleDataEventImpl(event);

/// Routes [n] through [coll]'s value-event branch directly — bypasses
/// the regex dispatcher; tests exercise the value-handler in isolation.
@visibleForTesting
Future<void> handleObjNotificationForTest(
  AtCollection<dynamic> coll,
  AtNotification n,
) =>
    coll._handleObjNotificationImpl(n);

/// Routes [n] through [coll]'s sub-collection-event branch directly.
@visibleForTesting
Future<void> handleSubObjNotificationForTest(
  AtCollection<dynamic> coll,
  AtNotification n,
) =>
    coll._handleSubObjNotificationImpl(n);

/// Clears the process-global factory registry so tests can start from
/// a known empty state. The registry is a `static` cache on
/// [AtCollection] used by `registerFactory` / `setUpFromAtSign`; tests
/// call this in setUp/tearDown to avoid cross-test pollution.
@visibleForTesting
void clearFactoriesForTest() => AtCollection._clearFactoriesForTestImpl();

/// Clears the warned-tag set used to suppress repeated
/// `missing factory for type tag` log lines.
@visibleForTesting
void clearMissingFactoryWarningsForTest() =>
    AtCollection._clearMissingFactoryWarningsForTestImpl();

/// Opens [spec] on [parentItem] using [parentColl]'s context. Test-only
/// because the production call-site is hidden behind
/// [AtCollection.subCollection] — the spec object isn't directly
/// constructed by app code.
@visibleForTesting
AtCollection<U> openSubSpecForTest<T, U>(
  SubSpec<U> spec,
  AtCollection<T> parentColl,
  CItem<T> parentItem,
) =>
    spec._openOnForTest<T>(parentColl, parentItem);

/// Builds a [CmpPredicate] with the given parts, bypassing the
/// [PathField] operator path. Tests use this to exercise reserved
/// [PredicateOp] values that don't yet have a corresponding operator.
@visibleForTesting
CmpPredicate cmpPredicateForTest(
  PathField<dynamic> field,
  PredicateOp op,
  Object? value,
) =>
    CmpPredicate._(field, op, value);
