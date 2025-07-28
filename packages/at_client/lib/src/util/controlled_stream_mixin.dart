import 'dart:async'
    show
        StreamController,
        StreamSubscription,
        FutureOr,
        StreamConsumer,
        EventSink,
        StreamTransformer;

import 'package:meta/meta.dart' show experimental, protected;

@experimental

/// Use this mixin with care, improper use of the controller can introduce
/// lifecycle issues with the underlying StreamController. Certain functions in
/// a [StreamController] will alter / consume the stream, so they may not be
/// used unless one of those kinds of operations is called by the caller.
mixin ControlledStream<T> implements Stream<T> {
  @protected
  final StreamController<T> streamController = StreamController<T>();
  Stream<T> get _stream => streamController.stream;

  @override
  Future<bool> any(bool Function(T element) test) => _stream.any(test);

  @override
  Stream<T> asBroadcastStream(
          {void Function(StreamSubscription<T> subscription)? onListen,
          void Function(StreamSubscription<T> subscription)? onCancel}) =>
      _stream.asBroadcastStream(onListen: onListen, onCancel: onCancel);

  @override
  Stream<E> asyncExpand<E>(Stream<E>? Function(T event) convert) =>
      _stream.asyncExpand<E>(convert);

  @override
  Stream<E> asyncMap<E>(FutureOr<E> Function(T event) convert) =>
      _stream.asyncMap<E>(convert);

  @override
  Stream<R> cast<R>() => _stream.cast<R>();

  @override
  Future<bool> contains(Object? needle) => _stream.contains(needle);

  @override
  Stream<T> distinct([bool Function(T previous, T next)? equals]) =>
      _stream.distinct(equals);

  @override
  Future<E> drain<E>([E? futureValue]) => _stream.drain<E>(futureValue);

  @override
  Future<T> elementAt(int index) => _stream.elementAt(index);

  @override
  Future<bool> every(bool Function(T element) test) => _stream.every(test);

  @override
  Stream<S> expand<S>(Iterable<S> Function(T element) convert) =>
      _stream.expand<S>(convert);

  @override
  Future<T> get first => _stream.first;

  @override
  Future<T> firstWhere(bool Function(T element) test, {T Function()? orElse}) =>
      _stream.firstWhere(test, orElse: orElse);

  @override
  Future<S> fold<S>(
          S initialValue, S Function(S previous, T element) combine) =>
      _stream.fold<S>(initialValue, combine);

  @override
  Future<void> forEach(void Function(T element) action) =>
      _stream.forEach(action);

  @override
  Stream<T> handleError(Function onError,
          {bool Function(dynamic error)? test}) =>
      _stream.handleError(onError, test: test);

  @override
  bool get isBroadcast => _stream.isBroadcast;

  @override
  Future<bool> get isEmpty => _stream.isEmpty;

  @override
  Future<String> join([String separator = ""]) => _stream.join(separator);

  @override
  Future<T> get last => _stream.last;

  @override
  Future<T> lastWhere(bool Function(T element) test, {T Function()? orElse}) =>
      _stream.lastWhere(test, orElse: orElse);

  @override
  Future<int> get length => _stream.length;

  @override
  StreamSubscription<T> listen(void Function(T event)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  Stream<S> map<S>(S Function(T event) convert) => _stream.map(convert);

  @override
  Future pipe(StreamConsumer<T> streamConsumer) => _stream.pipe(streamConsumer);

  @override
  Future<T> reduce(T Function(T previous, T element) combine) =>
      _stream.reduce(combine);

  @override
  Future<T> get single => _stream.single;

  @override
  Future<T> singleWhere(bool Function(T element) test,
          {T Function()? orElse}) =>
      _stream.singleWhere(test, orElse: orElse);

  @override
  Stream<T> skip(int count) => _stream.skip(count);

  @override
  Stream<T> skipWhile(bool Function(T element) test) => _stream.skipWhile(test);

  @override
  Stream<T> take(int count) => _stream.take(count);

  @override
  Stream<T> takeWhile(bool Function(T element) test) => _stream.takeWhile(test);

  @override
  Stream<T> timeout(Duration timeLimit,
          {void Function(EventSink<T> sink)? onTimeout}) =>
      _stream.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<List<T>> toList() => _stream.toList();

  @override
  Future<Set<T>> toSet() => _stream.toSet();

  @override
  Stream<S> transform<S>(StreamTransformer<T, S> streamTransformer) =>
      _stream.transform<S>(streamTransformer);

  @override
  Stream<T> where(bool Function(T event) test) => _stream.where(test);
}
