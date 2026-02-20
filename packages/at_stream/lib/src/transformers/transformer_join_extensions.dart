import 'dart:async';

import 'package:async/async.dart' show StreamSinkTransformer;
import 'package:stream_channel/stream_channel.dart'
    show StreamChannel, StreamChannelTransformer;

// TODO(@xavierchanth): write tests

// Provides .join on transformers for Stream, StreamSink, and StreamChannel.
// When used on a Transformer<R,S>, you can join a Transformer<S,T> to it.
// This will return a Transformer<R,T> (joining the two).

// StreamChannel (package:stream_channel)

extension StreamChannelTransformerJoin<R, S> on StreamChannelTransformer<R, S> {
  StreamChannelTransformer<R, T> join<T>(StreamChannelTransformer<S, T> other) {
    return _StreamChannelTransformerJoined(this, other);
  }
}

class _StreamChannelTransformerJoined<R, S, T>
    implements StreamChannelTransformer<R, T> {
  final StreamChannelTransformer<R, S> _first;
  final StreamChannelTransformer<S, T> _second;
  const _StreamChannelTransformerJoined(this._first, this._second);
  @override
  StreamChannel<R> bind(StreamChannel<T> channel) {
    return _first.bind(_second.bind(channel));
  }
}

// StreamSink (package:async)

extension StreamSinkTransformerJoin<R, S> on StreamSinkTransformer<R, S> {
  StreamSinkTransformer<R, T> join<T>(StreamSinkTransformer<S, T> other) {
    return _StreamSinkTransformerJoined(this, other);
  }
}

class _StreamSinkTransformerJoined<R, S, T>
    implements StreamSinkTransformer<R, T> {
  final StreamSinkTransformer<R, S> _first;
  final StreamSinkTransformer<S, T> _second;
  const _StreamSinkTransformerJoined(this._first, this._second);
  @override
  StreamSink<R> bind(StreamSink<T> sink) {
    return _first.bind(_second.bind(sink));
  }
}

// Stream (dart:async)

extension StreamTranformerJoin<R, S> on StreamTransformer<R, S> {
  StreamTransformer<R, T> join<T>(StreamTransformer<S, T> other) {
    return StreamTransformer<R, T>.fromBind((Stream<R> stream) {
      return other.bind(bind(stream));
    });
  }
}
