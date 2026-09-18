import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/at_connection.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart';

///Listener class for messages received by [RemoteSecondary]
class OutboundMessageListener {
  final logger = AtSignLogger('OutboundMessageListener');
  late ByteBuffer _buffer;
  final Queue _queue = Queue();

  /// Completed to wake any pending [read] the moment a response is queued.
  ///
  /// Replaced rather than reused, because a [Completer] completes once. Null
  /// whenever nobody is waiting, so a response arriving with no reader costs
  /// nothing.
  Completer<void>? _responseQueued;

  /// Set once the connection this listener reads has gone away.
  ///
  /// Never cleared: [AtLookupImpl.createConnection] builds a fresh listener
  /// with every connection, so a listener whose socket has died is never
  /// reused for a live one.
  bool _connectionGone = false;
  bool _closedLocally = false;

  final AtConnection _connection;

  /// Where `notification:` messages go, if anywhere.
  ///
  /// A notification answers no request, so nothing is waiting to read it: with
  /// no callback installed there is nowhere to put one and it is dropped, with
  /// a warning saying so.
  void Function(String notification)? onNotification;
  final int newLineCodeUnit = 10;
  late DateTime _lastReceivedTime;

  OutboundMessageListener(this._connection, {int bufferCapacity = 10240000}) {
    _buffer = ByteBuffer(capacity: bufferCapacity);
  }

  /// The subscription to the transport, kept so delivery can be stopped.
  ///
  /// This used to be discarded. Keeping it is what lets back-pressure reach
  /// the far end: pausing here stops reading the transport, so bytes accumulate
  /// in the kernel receive buffer and TCP eventually closes the window on the
  /// atServer. Without it a slow consumer's only option is to buffer without
  /// bound in this process, which is not back-pressure - it is a memory leak
  /// that ends in an overflow.
  StreamSubscription<List<int>>? _inboundSubscription;

  /// Listens to the underlying connection's inbound bytes.
  /// @throws [AtConnectException] if the connection is not yet created
  void listen() {
    logger.finest('Calling inbound.listen within runZonedGuarded block');

    runZonedGuarded(() {
      _inboundSubscription = _connection.inbound
          .listen(messageHandler, onDone: onSocketDone, onError: onSocketError);
    }, (Object error, StackTrace st) {
      logger.warning(
          'runZonedGuarded received socket error $error - calling onSocketError() to close connection');
      onSocketError(error);
    });
  }

  /// Whether delivery from the transport is currently stopped.
  bool get isDeliveryPaused => _inboundSubscription?.isPaused ?? false;

  /// Stop reading the transport.
  ///
  /// ⚠️ Pauses are COUNTED by [StreamSubscription] - measured, not assumed:
  /// two `pause()` calls need two `resume()` calls before delivery restarts.
  /// So every call here needs exactly one matching [resumeDelivery]. Wiring
  /// these to a [StreamController]'s `onPause`/`onResume` satisfies that by
  /// construction, which is why the notification stream drives them rather
  /// than callers doing it by hand.
  ///
  /// A no-op before [listen] has been called, and a no-op is right: there is
  /// no delivery to stop.
  void pauseDelivery() => _inboundSubscription?.pause();

  /// Resume reading the transport. Safe when not paused - probed, it does not
  /// throw - so an unmatched resume costs nothing.
  void resumeDelivery() => _inboundSubscription?.resume();

  /// Called after the connection has been closed because the far end went
  /// away - either cleanly (`onDone`) or with an error (`onError`).
  ///
  /// The listener knows the socket died before anything else does, and until
  /// now it kept that to itself: it closed the connection and returned, so a
  /// subscriber waiting on notifications simply stopped hearing anything, with
  /// no event distinguishing "the atServer is quiet" from "the socket is
  /// gone". Whoever owns reconnection needs that difference.
  void Function()? onDisconnect;

  void _notifyDisconnect() {
    final callback = onDisconnect;
    if (callback == null) return;
    try {
      callback();
    } catch (e, st) {
      logger.shout('onDisconnect threw $e - reconnection may not happen\n$st');
    }
  }

  /// Logs the error and closes the [OutboundConnection]
  @visibleForTesting
  void onSocketError(Object error) async {
    // logger.finest('outbound error handler called - calling closeConnection - error was $error and stackTrace was\n$stackTrace');
    logger.finest(
        'outbound socket onError handler called - calling closeConnection - error was $error');
    await closeConnection();
    logger.finest(
        'outbound socket onError handler called - closeConnection complete');
    _notifyDisconnect();
  }

  /// Closes the [OutboundConnection]
  @visibleForTesting
  void onSocketDone() async {
    logger.finest(
        'outbound socket onDone handler called - calling closeConnection');
    await closeConnection();
    logger.finest(
        'outbound socket onDone handler called - closeConnection complete');
    _notifyDisconnect();
  }

  /// Reads the connection a line at a time and hands each message to whatever
  /// it belongs to.
  ///
  /// The atServer writes one message at a time and every message ends at a
  /// newline, so a line IS a message: nothing has to be inferred from where a
  /// prompt falls. A message may carry the prompt for the next command at its
  /// start - `@alice@data:ok` - which [_stripPrompt] takes off, and what is
  /// left says which kind of message it is. `data:` and `error:` answer a
  /// request this client made, so they go to the reader waiting for one;
  /// `notification:` was not asked for and goes to [onNotification]; a kind
  /// added to the protocol later takes its own route here rather than being
  /// mistaken for either.
  ///
  /// Throws a [BufferOverFlowException] if the buffer cannot hold the data.
  Future<void> messageHandler(List<int> data) async {
    _lastReceivedTime = DateTime.now();
    _checkBufferOverFlow(data);
    for (final byte in data) {
      _buffer.addByte(byte);
      if (byte == newLineCodeUnit) {
        _deliverMessage();
      }
    }
  }

  /// Delivers the message the buffer just completed.
  void _deliverMessage() {
    final bytes = _buffer.getData();
    final body = bytes.sublist(0, bytes.length - 1);
    _buffer.clear();
    if (body.isEmpty) return;
    final String message;
    try {
      message = _stripPrompt(utf8.decode(body));
    } catch (e) {
      // A line always holds whole UTF-8 sequences - a newline byte cannot be
      // part of one - so this is the atServer sending bytes that are not
      // UTF-8 at all. Dropping the line keeps it out of the next message.
      logger.warning('Undecodable line dropped: $e');
      return;
    }
    if (message.isEmpty) return;
    if (message.startsWith('notification:')) {
      _deliverNotification(message);
      return;
    }
    logger.finer('RECEIVED $message');
    _queue.add(message);
    _wakeReaders();
  }

  void _deliverNotification(String notification) {
    final callback = onNotification;
    if (callback == null) {
      // Warned, not swallowed: a notification nobody routed is gone for good,
      // and a client that never hears it cannot tell that from one the
      // atServer never sent.
      logger.warning(
          'Notification dropped - nothing is listening for one: $notification');
      return;
    }
    logger.finer('NOTIFICATION $notification');
    try {
      callback(notification);
    } catch (e, st) {
      logger.shout('onNotification threw $e - notification dropped\n$st');
    }
  }

  /// The methods verifies if buffer has the capacity to accept the data.
  ///
  /// Throw BufferOverFlowException if data length exceeds the buffer capacity
  void _checkBufferOverFlow(List<int> data) {
    if (_buffer.isOverFlow(data)) {
      int bufferLength = _buffer.length() + data.length;
      _buffer.clear();
      throw BufferOverFlowException(
          'data length exceeded the buffer limit. Data length : $bufferLength and Buffer capacity ${_buffer.capacity}');
    }
  }

  /// The method accepts the result (server response) and trim's the prompt from the response
  /// and returns the actual response.
  ///
  /// A response with no colon has no prompt to strip and is returned as it
  /// stands. The bare `@<atSign>@` that completes the handshake is exactly
  /// that, and [_isValidResponse] accepts it, so without this guard
  /// `substring(0, -1)` throws a RangeError from inside the socket's data
  /// handler - which `runZonedGuarded` turns into a socket error, destroying a
  /// healthy connection and leaving the caller with a timeout that names the
  /// wrong cause.
  String _stripPrompt(String result) {
    var colonIndex = result.indexOf(':');
    if (colonIndex == -1) {
      return result;
    }
    var responsePrefix = result.substring(0, colonIndex);
    var response = result.substring(colonIndex);
    if (responsePrefix.contains('@')) {
      responsePrefix =
          responsePrefix.substring(responsePrefix.lastIndexOf('@') + 1);
    }
    return '$responsePrefix$response';
  }

  void _wakeReaders() {
    final waiter = _responseQueued;
    _responseQueued = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }

  /// Fails anything waiting in [read], at once, because the connection is gone.
  ///
  /// A response can only arrive on the socket this listener reads, so once that
  /// socket is gone a pending [read] is waiting for something that can never
  /// come. That wait is not free: `AtLookupImpl._process` holds
  /// `requestResponseMutex` across it, so the next request on the same
  /// AtLookupImpl queues behind a dead one for the whole transient budget -
  /// measured at 30 seconds, long enough to blow past a test's own timeout and
  /// long enough that an application reads it as a hang.
  ///
  /// Deliberately NOT the same thing as a timeout: nothing timed out. The
  /// caller is told the connection went away, which is both true and
  /// actionable, where `AtTimeoutException` would send it looking at the
  /// atServer's latency.
  ///
  /// A response already parsed and queued is still returned - those bytes
  /// arrived while the connection was alive and the caller is owed them.
  ///
  /// [closedLocally] says this side closed the connection on purpose, and the
  /// failure the reader raises says so, because a caller told the connection
  /// went away goes looking at the network for something it did itself.
  void abortPendingRequests({bool closedLocally = false}) {
    _connectionGone = true;
    _closedLocally = _closedLocally || closedLocally;
    final waiter = _responseQueued;
    _responseQueued = null;
    if (waiter != null && !waiter.isCompleted) {
      // Logged because it is otherwise invisible: the request simply fails, and
      // a failure attributed to the atServer rather than to the connection
      // being closed underneath it sends the reader to the wrong end.
      logger.info('Connection closed${closedLocally ? ' by this client' : ''} '
          'with a request in flight - failing it now rather than waiting out '
          'its response budget');
      waiter.complete();
    }
  }

  /// Reads the response sent by remote socket from the queue.
  ///
  /// Two independent budgets bound the wait, and they measure different things:
  ///
  /// - [maxWaitMilliSeconds] is the whole response, from this call to the
  ///   terminating byte. Defaults to [AtNetworkTimeouts.defaultResponseBudget].
  /// - [transientWaitTimeMillis] is the gap between *chunks*. Every byte the
  ///   socket delivers moves [_lastReceivedTime], so this restarts whenever the
  ///   atServer is still sending. Defaults to
  ///   [AtNetworkTimeouts.effectiveDefault].
  ///
  /// Passing null for either takes the default at the time of the call, so a
  /// process that moves `AtNetworkTimeouts.defaultTimeout` at startup moves
  /// this too.
  ///
  /// The wait is event-driven: this sleeps until a response is queued or until
  /// the nearer of the two deadlines, whichever happens first. It does not poll,
  /// so a response is surfaced as soon as its last byte is parsed rather than up
  /// to a polling interval later.
  Future<String> read({
    int? maxWaitMilliSeconds,
    int? transientWaitTimeMillis,
  }) async {
    final maxWait = maxWaitMilliSeconds ??
        AtNetworkTimeouts.defaultResponseBudget.inMilliseconds;
    final transientWait = transientWaitTimeMillis ??
        AtNetworkTimeouts.effectiveDefault.inMilliseconds;
    String result;
    _lastReceivedTime = DateTime.now();
    var startTime = DateTime.now();
    while (true) {
      if (_queue.isNotEmpty) {
        result = _queue.removeFirst();
        // result from another secondary is either data or a @<atSign>@ denoting complete
        // of the handshake
        if (_isValidResponse(result)) {
          return result;
        }
        //ignore any other response
        _buffer.clear();
        throw AtLookUpException('AT0014', 'Unexpected response found');
      }

      // Checked after the queue and before the deadlines: a response that
      // arrived before the connection died is still owed to the caller, and a
      // connection that has gone will never produce another one.
      if (_connectionGone) {
        _buffer.clear();
        throw ConnectionInvalidException(_closedLocally
            ? 'The connection was closed by this client before a response '
                'arrived'
            : 'The connection went away before a response arrived');
      }

      // if currentTime - startTime  is greater than maxWait throw AtTimeoutException
      final sinceStart = DateTime.now().difference(startTime).inMilliseconds;
      if (sinceStart > maxWait) {
        _buffer.clear();
        await closeConnection();
        throw AtTimeoutException(
            'Full response not received after $maxWait millis from remote atServer');
      }
      // if no data is received from server and if currentTime - _lastReceivedTime is greater than
      // transientWait throw AtTimeoutException
      final sinceReceived =
          DateTime.now().difference(_lastReceivedTime).inMilliseconds;
      if (sinceReceived > transientWait) {
        _buffer.clear();
        await closeConnection();
        throw AtTimeoutException(
            'Waited for $transientWait millis. No response after $_lastReceivedTime ');
      }

      // Sleep until a response is queued or the nearer deadline passes. The
      // extra millisecond matters: both checks above are strict `>`, so waking
      // exactly ON a deadline would find neither exceeded and sleep again for
      // zero, spinning until the clock ticked over.
      //
      // A chunk that does not complete a response does not wake anything. It
      // does not need to - it can only push the transient deadline further
      // out, and the wake that was already scheduled recomputes it from
      // _lastReceivedTime and sleeps again.
      final untilDeadline = Duration(
          milliseconds:
              min(maxWait - sinceStart, transientWait - sinceReceived) + 1);
      _responseQueued ??= Completer<void>();
      await _responseQueued!.future.timeout(untilDeadline, onTimeout: () {});
    }
  }

  bool _isValidResponse(String result) {
    return result.startsWith('data:') ||
        result.startsWith('stream:') ||
        result.startsWith('error:') ||
        (result.startsWith('@') && result.endsWith('@'));
  }

  @visibleForTesting
  Duration? delayBeforeClose;

  @visibleForTesting
  Future<void> closeConnection() async {
    if (delayBeforeClose != null) {
      await Future.delayed(delayBeforeClose!);
    }
    // Before the close, so a reader woken by it finds the flag already set.
    // This covers the far end going away - `onSocketDone` and `onSocketError`
    // both arrive here. A close started anywhere else reaches
    // [abortPendingRequests] through `AtLookupImpl`.
    abortPendingRequests();
    await _connection.close();
  }
}
