import 'dart:async';

import 'package:at_client/at_client.dart' show AtClient, AtClientManager, AtNotification;
import 'package:at_commons/at_commons.dart' show AtKey, AtValue;
import 'package:meta/meta.dart';

abstract class KeyStreamMixin<T> implements Stream<T> {
  @visibleForTesting
  late StreamSubscription<AtNotification> notificationSubscription;

  @protected
  @visibleForTesting
  final StreamController<T> controller = StreamController();

  final Function(AtKey, AtValue) convert;
  final String? regex;
  final bool shouldGetKeys;
  final String? sharedBy;
  final String? sharedWith;

  KeyStreamMixin({
    required this.convert,
    this.regex,
    this.sharedBy,
    this.sharedWith,
    this.shouldGetKeys = true,
  }) {
    _init();
  }

  Future<void> _init() async {
    if (shouldGetKeys) getKeys();

    notificationSubscription = AtClientManager.getInstance()
        .notificationService
        .subscribe(shouldDecrypt: true, regex: regex)
        .listen(_notificationListener);
  }

  @visibleForTesting
  Future<void> getKeys() async {
    AtClient atClient = AtClientManager.getInstance().atClient;
    List<AtKey> keys = await atClient.getAtKeys(
      regex: regex,
      sharedBy: sharedBy,
      sharedWith: sharedWith,
    );

    for (AtKey key in keys) {
      atClient.get(key).then((AtValue value) {
        handleNotification(key, value, 'init');
      });
    }
  }

  void _notificationListener(AtNotification event) {
    AtKey key = AtKey.fromString(event.key);
    if (sharedBy != null && sharedBy != event.from) return;
    if (sharedWith != null && sharedWith != event.to) return;

    AtClientManager.getInstance().atClient.get(key).then(
      (AtValue value) {
        handleNotification(key, value, event.operation);
      },
    );
  }

  @protected
  // Possible operations are:
  //  'update', 'append', 'remove', 'delete', 'init', null
  void handleNotification(AtKey key, AtValue value, String? operation);

  void pause([Future<void>? resumeSignal]) => notificationSubscription.pause(resumeSignal);

  void resume() => notificationSubscription.resume();

  bool get isPaused => notificationSubscription.isPaused;

  Future<void> dispose() async {
    await Future.wait([controller.close(), notificationSubscription.cancel()]);
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
