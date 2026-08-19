import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

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
  final AtConnection _connection;
  Function? syncCallback;

  /// Where asynchronous `notification:` lines go, if anywhere.
  ///
  /// The atServer frames the two kinds of message differently. A verb response
  /// ends `\n@<atSign>@` - the newline, then the prompt saying it is ready for
  /// the next command. A notification is not a reply to anything, so no prompt
  /// follows it and it ends at a bare `\n`.
  ///
  /// While this is null the second framing is not applied at all and the
  /// listener behaves exactly as it did before it existed. That is deliberate:
  /// routing notifications to a callback nobody installed would drop them, and
  /// a dropped notification is indistinguishable from one the atServer never
  /// sent.
  void Function(String notification)? onNotification;
  final int newLineCodeUnit = 10;
  final int atCharCodeUnit = 64;
  late DateTime _lastReceivedTime;

  OutboundMessageListener(this._connection, {int bufferCapacity = 10240000}) {
    _buffer = ByteBuffer(capacity: bufferCapacity);
  }

  /// The subscription to the socket, kept so delivery can be stopped.
  ///
  /// This used to be discarded. Keeping it is what lets back-pressure reach
  /// the far end: pausing here stops reading the socket, so bytes accumulate
  /// in the kernel receive buffer and TCP eventually closes the window on the
  /// atServer. Without it a slow consumer's only option is to buffer without
  /// bound in this process, which is not back-pressure - it is a memory leak
  /// that ends in an overflow.
  StreamSubscription<Uint8List>? _socketSubscription;

  /// Listens to the underlying connection's socket if the connection is created.
  /// @throws [AtConnectException] if the connection is not yet created
  void listen() {
    logger.finest('Calling socket.listen within runZonedGuarded block');

    runZonedGuarded(() {
      _socketSubscription = _connection
          .getSocket()
          .listen(messageHandler, onDone: onSocketDone, onError: onSocketError);
    }, (Object error, StackTrace st) {
      logger.warning(
          'runZonedGuarded received socket error $error - calling onSocketError() to close connection');
      onSocketError(error);
    });
  }

  /// Whether delivery from the socket is currently stopped.
  bool get isDeliveryPaused => _socketSubscription?.isPaused ?? false;

  /// Stop reading the socket.
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
  void pauseDelivery() => _socketSubscription?.pause();

  /// Resume reading the socket. Safe when not paused - probed, it does not
  /// throw - so an unmatched resume costs nothing.
  void resumeDelivery() => _socketSubscription?.resume();

  /// Logs the error and closes the [OutboundConnection]
  @visibleForTesting
  void onSocketError(Object error) async {
    // logger.finest('outbound error handler called - calling closeConnection - error was $error and stackTrace was\n$stackTrace');
    logger.finest(
        'outbound socket onError handler called - calling closeConnection - error was $error');
    await closeConnection();
    logger.finest(
        'outbound socket onError handler called - closeConnection complete');
  }

  /// Closes the [OutboundConnection]
  @visibleForTesting
  void onSocketDone() async {
    logger.finest(
        'outbound socket onDone handler called - calling closeConnection');
    await closeConnection();
    logger.finest(
        'outbound socket onDone handler called - closeConnection complete');
  }

  /// Handles messages on the inbound client's connection and calls the verb executor
  /// Closes the inbound connection in case of any error.
  /// Throw a [BufferOverFlowException] if buffer is unable to hold incoming data
  Future<void> messageHandler(List<int> data) async {
    String result;
    int offset;
    _lastReceivedTime = DateTime.now();
    // check buffer overflow
    _checkBufferOverFlow(data);
    // If the data contains a new line character, add until the new line char to buffer
    // Everything before the LAST newline is appended without being examined
    // for the `\n@` terminator, and that is not an optimisation - it is what
    // makes multi-line values work. A `data:` value may itself contain `\n@`
    // (a key name follows a newline inside the value), and inspecting those
    // bytes would end the response early and truncate it.
    //
    // Notifications need the opposite: they end at a bare newline, so every
    // newline in that skipped region IS a message boundary. Hence two passes
    // over it - the notification check byte by byte, the `\n@` check only from
    // the last newline on, exactly as before.
    if (data.contains(newLineCodeUnit)) {
      offset = data.lastIndexOf(newLineCodeUnit);
      final head = data.getRange(0, offset).toList();
      if (onNotification == null) {
        _buffer.append(head);
      } else {
        for (final byte in head) {
          _buffer.addByte(byte);
          if (byte == newLineCodeUnit) {
            _routeIfNotification();
          }
        }
      }
    } else {
      offset = 0;
    }
    // Loop from last index to until the end of data.
    // If a new line character and followed by @ character is found, then it is end
    // of server response. process the data.
    // Else add the byte to buffer.
    for (int element = offset; element < data.length; element++) {
      // If element is @ character and lastCharacter in the buffer is \n,
      // then complete data is received. process it.
      if (data[element] == atCharCodeUnit &&
          (_buffer.length() > 0 && _buffer.getData().last == newLineCodeUnit)) {
        // remove the terminating character (last \n) from the server response.
        // preserve other new line characters.
        List<int> temp = (_buffer.getData().toList())..removeLast();
        result = utf8.decode(temp);
        result = _stripPrompt(result);
        logger.finer('RECEIVED $result');
        _queue.add(result);
        _wakeReaders();
        //clear the buffer after adding result to queue
        _buffer.clear();
        _buffer.addByte(data[element]);
      } else {
        _buffer.addByte(data[element]);
        if (data[element] == newLineCodeUnit && onNotification != null) {
          _routeIfNotification();
        }
      }
    }
  }

  /// Surface the buffer if it holds a complete notification.
  ///
  /// Called only when the buffer just gained a newline. A verb response whose
  /// VALUE contains newlines is left alone, because the test is on the
  /// buffer's prefix: a multi-line value still begins `data:` or `error:`,
  /// never `notification:`.
  void _routeIfNotification() {
    final bytes = _buffer.getData();
    if (bytes.isEmpty || bytes.last != newLineCodeUnit) return;
    final body = bytes.sublist(0, bytes.length - 1);
    if (body.isEmpty) return;
    final String stripped;
    try {
      stripped = _stripPrompt(utf8.decode(body));
    } catch (_) {
      // Not decodable yet - more bytes are coming. Leave the buffer alone.
      return;
    }
    if (!stripped.startsWith('notification:')) return;

    logger.finer('NOTIFICATION $stripped');
    _buffer.clear();
    try {
      onNotification!(stripped);
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
    await _connection.close();
  }
}
