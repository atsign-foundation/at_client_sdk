import 'dart:async';
import 'dart:io';

import 'package:at_utils/at_logger.dart';

class PseudoServerSocket implements ServerSocket {
  final AtSignLogger logger = AtSignLogger(' AtServerSocket ');
  final SecureServerSocket _serverSocket;
  final StreamController<Socket> sc =
      StreamController<Socket>.broadcast(sync: true);

  PseudoServerSocket(this._serverSocket);

  @override
  int get port => _serverSocket.port;

  @override
  InternetAddress get address => _serverSocket.address;

  @override
  Future<ServerSocket> close() async {
    await sc.close();
    return this;
  }

  add(Socket socket) {
    logger.info('add was called with socket: $socket');
    sc.add(socket);
  }

  // Can ignore everything from this point on, it's just the implementation
  // of the Stream<Socket> interface.
  //
  // All calls to the Stream<Socket> methods are implemented by delegating
  // the calls to the StreamController's stream

  @override
  Future<bool> any(bool Function(Socket element) test) {
    return sc.stream.any(test);
  }

  @override
  Stream<Socket> asBroadcastStream(
      {void Function(StreamSubscription<Socket> subscription)? onListen,
      void Function(StreamSubscription<Socket> subscription)? onCancel}) {
    return sc.stream.asBroadcastStream(onListen: onListen, onCancel: onCancel);
  }

  @override
  Stream<E> asyncExpand<E>(Stream<E>? Function(Socket event) convert) {
    return sc.stream.asyncExpand(convert);
  }

  @override
  Stream<E> asyncMap<E>(FutureOr<E> Function(Socket event) convert) {
    return sc.stream.asyncMap(convert);
  }

  @override
  Stream<R> cast<R>() {
    return sc.stream.cast<R>();
  }

  @override
  Future<bool> contains(Object? needle) {
    return sc.stream.contains(needle);
  }

  @override
  Stream<Socket> distinct(
      [bool Function(Socket previous, Socket next)? equals]) {
    return sc.stream.distinct(equals);
  }

  @override
  Future<E> drain<E>([E? futureValue]) {
    return sc.stream.drain(futureValue);
  }

  @override
  Future<Socket> elementAt(int index) {
    return sc.stream.elementAt(index);
  }

  @override
  Future<bool> every(bool Function(Socket element) test) {
    return sc.stream.every(test);
  }

  @override
  Stream<S> expand<S>(Iterable<S> Function(Socket element) convert) {
    return sc.stream.expand(convert);
  }

  @override
  Future<Socket> get first => sc.stream.first;

  @override
  Future<Socket> firstWhere(bool Function(Socket element) test,
      {Socket Function()? orElse}) {
    return sc.stream.firstWhere(test, orElse: orElse);
  }

  @override
  Future<S> fold<S>(
      S initialValue, S Function(S previous, Socket element) combine) {
    return sc.stream.fold(initialValue, combine);
  }

  @override
  Future<void> forEach(void Function(Socket element) action) {
    return sc.stream.forEach(action);
  }

  @override
  Stream<Socket> handleError(Function onError,
      {bool Function(dynamic error)? test}) {
    return sc.stream.handleError(onError, test: test);
  }

  @override
  bool get isBroadcast => sc.stream.isBroadcast;

  @override
  Future<bool> get isEmpty => sc.stream.isEmpty;

  @override
  Future<String> join([String separator = ""]) {
    return sc.stream.join(separator);
  }

  @override
  Future<Socket> get last => sc.stream.last;

  @override
  Future<Socket> lastWhere(bool Function(Socket element) test,
      {Socket Function()? orElse}) {
    return sc.stream.lastWhere(test, orElse: orElse);
  }

  @override
  Future<int> get length => sc.stream.length;

  @override
  StreamSubscription<Socket> listen(void Function(Socket event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return sc.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  Stream<S> map<S>(S Function(Socket event) convert) {
    return sc.stream.map(convert);
  }

  @override
  Future pipe(StreamConsumer<Socket> streamConsumer) {
    return sc.stream.pipe(streamConsumer);
  }

  @override
  Future<Socket> reduce(
      Socket Function(Socket previous, Socket element) combine) {
    return sc.stream.reduce(combine);
  }

  @override
  Future<Socket> get single => sc.stream.single;

  @override
  Future<Socket> singleWhere(bool Function(Socket element) test,
      {Socket Function()? orElse}) {
    return sc.stream.singleWhere(test, orElse: orElse);
  }

  @override
  Stream<Socket> skip(int count) {
    return sc.stream.skip(count);
  }

  @override
  Stream<Socket> skipWhile(bool Function(Socket element) test) {
    return sc.stream.skipWhile(test);
  }

  @override
  Stream<Socket> take(int count) {
    return sc.stream.take(count);
  }

  @override
  Stream<Socket> takeWhile(bool Function(Socket element) test) {
    return sc.stream.takeWhile(test);
  }

  @override
  Stream<Socket> timeout(Duration timeLimit,
      {void Function(EventSink<Socket> sink)? onTimeout}) {
    return sc.stream.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<List<Socket>> toList() {
    return sc.stream.toList();
  }

  @override
  Future<Set<Socket>> toSet() {
    return sc.stream.toSet();
  }

  @override
  Stream<S> transform<S>(StreamTransformer<Socket, S> streamTransformer) {
    return sc.stream.transform(streamTransformer);
  }

  @override
  Stream<Socket> where(bool Function(Socket event) test) {
    return sc.stream.where(test);
  }
}
