import 'dart:async';

import 'package:at_client/at_client.dart'
    show AtClient, AtClientManager, AtNotification, SyncProgress, SyncProgressListener, SyncStatus;
import 'package:at_client/src/listener/at_sign_change_listener.dart' show AtSignChangeListener;
import 'package:at_client/src/listener/switch_at_sign_event.dart' show SwitchAtSignEvent;
import 'package:at_client/src/service/sync_service_impl.dart' show KeyInfo;
// ignore: unused_shown_name
import 'package:at_commons/at_commons.dart' show AtException, AtKey, AtValue;
import 'package:at_utils/at_logger.dart';

import 'package:meta/meta.dart';

/// [KeyStreamMixin] is an abstraction around the notification subsystem which is able to convert notification
/// subscriptions into streams that are more useful to the developer.
///
/// [KeyStreamMixin] provides three filters for values: [regex], [sharedBy], and [sharedWith]. These filters follow the
/// same behaviours as the rest of the sdk.
///
/// [KeyStreamMixin] initializes a [StreamSubscription<AtNotification>] and listens for incoming notifications. When a
/// notification is received, [KeyStreamMixin] calls atClient.get() on the Key, and calls handleNotification with the
/// resulting value. [handleStreamEvent] is an abstract function which defines how values get added to the stream.
/// The operation on handleNotfication is identical to that of [AtNotification.operation] with the exception of the
/// additional 'init' operation, which is used to identify a key which was initialized with the stream (when
/// [shouldGetKeys] is true).
abstract class KeyStreamMixin<T> implements Stream<T> {
  late AtClientManager _atClientManager;

  static final AtSignLogger _logger = AtSignLogger('KeyStream');

  /// An internal controller used to manage this Stream interface.
  @protected
  @visibleForTesting
  final StreamController<T> controller = StreamController();

  /// {@template KeyStreamConvert}
  /// [convert] is a required conversion function for converting [AtKey]:[AtValue] pairs from notifications into
  /// elements of this Stream or Stream's collection.
  /// {@endtemplate}
  final Function(AtKey key, AtValue value) convert;

  /// {@template KeyStreamRegex}
  /// [regex] is a regex pattern to filter notifications on.
  ///
  /// You can provide [sharedBy] or [sharedWith] as parts of this regex expression, or you can provide them separately.
  /// {@endtemplate}
  final String? regex;

  /// {@template KeyStreamSharedBy}
  /// Use [sharedBy] to filter to only keys that were sent by [sharedBy].
  ///
  /// This value is a single atsign, use regex if you would like to filter on multiple atsigns.
  /// {@endtemplate}
  final String? sharedBy;

  /// {@template KeyStreamSharedWith}
  /// Use [sharedWith] to filter to only keys that were sent to [sharedWith].
  ///
  /// This value is a single atsign, use regex if you would like to filter on multiple atsigns.
  /// {@endtemplate}
  final String? sharedWith;

  /// {@template KeyStreamShouldGetKeys}
  /// When [shouldGetKeys] is [true] this Stream should be preloaded with keys that match [regex], [sharedBy], and
  /// [sharedWith].
  /// {@endtemplate}
  final bool shouldGetKeys;

  /// {@template KeyStreamOnError}
  /// Callback function when an error occurs in the keystream.
  /// {@endtemplate}
  late final FutureOr<void> Function(Object exception) onError;

  @visibleForTesting
  bool disposeOnAtsignChange = true;

  KeyStreamMixin({
    required this.convert,
    this.regex,
    this.sharedBy,
    this.sharedWith,
    this.shouldGetKeys = true,
    FutureOr<void> Function(Object exception)? onError,
    AtClientManager? atClientManager,
  }) {
    _logger.finer('init Keystream: $this');

    this.onError = onError ?? (Object e, [StackTrace? s]) => _logger.warning('Error in', e, s);

    _atClientManager = atClientManager ?? AtClientManager.getInstance();
    if (shouldGetKeys) getKeys();

    _atClientManager.syncService.addProgressListener(KeyStreamProgressListener(this));

    if (disposeOnAtsignChange) {
      _atClientManager.listenToAtSignChange(KeyStreamDisposeListener(this));
    }
  }

  /// A function that preloads this Stream with keys that match [regex], [sharedBy], and [sharedWith].
  ///
  /// This calls handleNotification with the 'init' operation.
  @visibleForTesting
  Future<void> getKeys() async {
    _logger.finer('getting keys');
    AtClient atClient = _atClientManager.atClient;
    List<AtKey> keys = await atClient.getAtKeys(
      regex: regex,
      sharedBy: sharedBy,
      sharedWith: sharedWith,
    );

    for (AtKey key in keys) {
      atClient
          .get(key)
          .then(
            // ignore: unnecessary_cast
            (AtValue value) {
              _logger.finest('handleNotification key: $key, value: $value, operation: init');
              handleStreamEvent(key, value, 'init');
            } as void Function(AtValue),
          )
          .catchError(onError);
    }
  }

  /// Internal sync listener
  ///
  /// Validates the sharedBy and sharedWith values before
  void _onSyncProgressEvent(SyncProgress event) {
    switch (event.syncStatus) {
      case SyncStatus.failure:
      case null:
        onError('Sync failed in KeyStream $this');
        return;
      case SyncStatus.success:
        for (KeyInfo keyInfo in (event.keyInfoList ?? [])) {
          AtKey key = AtKey.fromString(keyInfo.key);
          // TODO check regex expression using same technique as notification service
          if (sharedBy != null && sharedBy != key.sharedBy) continue;
          if (sharedWith != null && sharedWith != key.sharedWith) continue;

          _atClientManager.atClient
              .get(key)
              .then(
                // ignore: unnecessary_cast
                (AtValue value) {
                  _logger.finest('handleNotification key: $key, value: $value, operation: ${event.operation}');
                  handleStreamEvent(key, value, event.operation);
                } as void Function(AtValue),
              )
              .catchError(onError);
        }
        break;
      default:
        break;
    }
  }

  @protected
  // TODO replace/remove operation
  // ? What happens to deleted keys in terms of feedback in the KeyInfo
  /// How to handle changes to keys.
  ///
  /// Possible operations are:
  /// 'update', 'append', 'remove', 'delete', 'init', null
  ///
  /// These operations are the same as [AtNotification], with an additional ['init'] operation
  /// which is used by [getKeys()] to indicate that this key was preloaded.
  void handleStreamEvent(AtKey key, AtValue value, String? operation);

  @Deprecated('Notification subsystem is no longer used by KeyStream.')
  void pause([Future<void>? resumeSignal]) {}

  @Deprecated('Notification subsystem is no longer used by KeyStream.')
  void resume() {}

  @Deprecated('Notification subsystem is no longer used by KeyStream.')
  bool get isPaused => true;

  // TODO update documentation (remove notification subscription reference)
  /// Closes the stream and cancels the notification subscription.
  ///
  /// Closes the stream:
  ///
  /// No further events can be added to a closed stream.
  ///
  /// The returned future is the same future provided by [done].
  /// It is completed when the stream listeners is done sending events,
  /// This happens either when the done event has been sent,
  /// or when the subscriber on a single-subscription stream is canceled.
  ///
  /// A broadcast stream controller will send the done event
  /// even if listeners are paused, so some broadcast events may not have been
  /// received yet when the returned future completes.
  ///
  /// If no one listens to a non-broadcast stream,
  /// or the listener pauses and never resumes,
  /// the done event will not be sent and this future will never complete.
  ///
  /// Cancels the notification subscription:
  ///
  /// After this call, the subscription no longer receives events.
  ///
  /// The stream may need to shut down the source of events and clean up after
  /// the subscription is canceled.
  ///
  /// Returns a future that is completed once the stream has finished
  /// its cleanup.
  ///
  /// Typically, cleanup happens when the stream needs to release resources.
  /// For example, a stream might need to close an open file (as an asynchronous
  /// operation). If the listener wants to delete the file after having
  /// canceled the subscription, it must wait for the cleanup future to complete.
  ///
  /// If the cleanup throws, which it really shouldn't, the returned future
  /// completes with that error.
  Future<void> dispose() async {
    _logger.finer('dispose KeyStream $this');
    await controller.close();
  }

  @override
  String toString() {
    return 'KeyStream{regex: $regex, sharedBy: $sharedBy, sharedWith: $sharedWith, shouldGetKeys: $shouldGetKeys}';
  }

  // Below are overrides for the Stream<T> Interface
  // All methods pass the call to controller.stream

  @override
  Future<bool> any(bool Function(T element) test) {
    return controller.stream.any(test);
  }

  @override
  Stream<T> asBroadcastStream(
      {void Function(StreamSubscription<T> subscription)? onListen,
      void Function(StreamSubscription<T> subscription)? onCancel}) {
    return controller.stream.asBroadcastStream(onListen: onListen, onCancel: onCancel);
  }

  @override
  Stream<E> asyncExpand<E>(Stream<E>? Function(T event) convert) {
    return controller.stream.asyncExpand(convert);
  }

  @override
  Stream<E> asyncMap<E>(FutureOr<E> Function(T event) convert) {
    return controller.stream.asyncMap(convert);
  }

  @override
  Stream<R> cast<R>() {
    return controller.stream.cast<R>();
  }

  @override
  Future<bool> contains(Object? needle) {
    return controller.stream.contains(needle);
  }

  @override
  Stream<T> distinct([bool Function(T previous, T next)? equals]) {
    return controller.stream.distinct(equals);
  }

  @override
  Future<E> drain<E>([E? futureValue]) {
    return controller.stream.drain(futureValue);
  }

  @override
  Future<T> elementAt(int index) {
    return controller.stream.elementAt(index);
  }

  @override
  Future<bool> every(bool Function(T element) test) {
    return controller.stream.every(test);
  }

  @override
  Stream<S> expand<S>(Iterable<S> Function(T element) convert) {
    return controller.stream.expand(convert);
  }

  @override
  Future<T> get first => controller.stream.first;

  @override
  Future<T> firstWhere(bool Function(T element) test, {T Function()? orElse}) {
    return controller.stream.firstWhere(test, orElse: orElse);
  }

  @override
  Future<S> fold<S>(S initialValue, S Function(S previous, T element) combine) {
    return controller.stream.fold(initialValue, combine);
  }

  @override
  Future forEach(void Function(T element) action) {
    return controller.stream.forEach(action);
  }

  @override
  Stream<T> handleError(Function onError, {bool Function(dynamic error)? test}) {
    return controller.stream.handleError(onError, test: test);
  }

  @override
  bool get isBroadcast => controller.stream.isBroadcast;

  @override
  Future<bool> get isEmpty => controller.stream.isEmpty;

  @override
  Future<String> join([String separator = ""]) {
    return controller.stream.join(separator);
  }

  @override
  Future<T> get last => controller.stream.last;

  @override
  Future<T> lastWhere(bool Function(T element) test, {T Function()? orElse}) {
    return controller.stream.lastWhere(test, orElse: orElse);
  }

  @override
  Future<int> get length => controller.stream.length;

  @override
  StreamSubscription<T> listen(void Function(T event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return controller.stream.listen(onData, onError: onError, cancelOnError: cancelOnError);
  }

  @override
  Stream<S> map<S>(S Function(T event) convert) {
    return controller.stream.map(convert);
  }

  @override
  Future pipe(StreamConsumer<T> streamConsumer) {
    return controller.stream.pipe(streamConsumer);
  }

  @override
  Future<T> reduce(T Function(T previous, T element) combine) {
    return controller.stream.reduce(combine);
  }

  @override
  Future<T> get single => controller.stream.single;

  @override
  Future<T> singleWhere(bool Function(T element) test, {T Function()? orElse}) {
    return controller.stream.singleWhere(test, orElse: orElse);
  }

  @override
  Stream<T> skip(int count) {
    return controller.stream.skip(count);
  }

  @override
  Stream<T> skipWhile(bool Function(T element) test) {
    return controller.stream.skipWhile(test);
  }

  @override
  Stream<T> take(int count) {
    return controller.stream.take(count);
  }

  @override
  Stream<T> takeWhile(bool Function(T element) test) {
    return controller.stream.takeWhile(test);
  }

  @override
  Stream<T> timeout(Duration timeLimit, {void Function(EventSink<T> sink)? onTimeout}) {
    return controller.stream.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<List<T>> toList() {
    return controller.stream.toList();
  }

  @override
  Future<Set<T>> toSet() {
    return controller.stream.toSet();
  }

  @override
  Stream<S> transform<S>(StreamTransformer<T, S> streamTransformer) {
    return controller.stream.transform(streamTransformer);
  }

  @override
  Stream<T> where(bool Function(T event) test) {
    return controller.stream.where(test);
  }
}

class KeyStreamDisposeListener extends AtSignChangeListener {
  final KeyStreamMixin _ref;
  KeyStreamDisposeListener(KeyStreamMixin ref) : _ref = ref;

  @override
  Future<void> listenToAtSignChange(SwitchAtSignEvent switchAtSignEvent) async {
    if (_ref.disposeOnAtsignChange) {
      await _ref.dispose();
    }
  }
}

class KeyStreamProgressListener extends SyncProgressListener {
  final KeyStreamMixin _ref;
  KeyStreamProgressListener(KeyStreamMixin ref) : _ref = ref;

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    _ref._onSyncProgressEvent(syncProgress);
  }
}
