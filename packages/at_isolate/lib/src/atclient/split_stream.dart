import 'dart:async' show Completer, StreamController;

Future<(List<T>, Stream<T>, void Function())> takeFromStream<T>(
  int count, Stream<T> stream, {
  void Function(T message, void Function() close)? handleMsg,
}) async{
  final completer = Completer<void>();
  final recvController = StreamController<T>();

  final taken = <T>[]; 
  stream.listen(
    (msg) {
      if (count-- > 0) {
        taken.add(msg);
        if(count == 0) completer.complete();
      } else {
        recvController.sink.add(msg);
      }
    },
    onDone: recvController.close,
  );

  await completer.future;

  void close() {
    if (!completer.isCompleted) completer.complete();
    recvController.close();
  }

  return (taken, recvController.stream, close);
}
