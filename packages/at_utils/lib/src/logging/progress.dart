class ProgressEvent {
  final DateTime time = DateTime.now();
  final String type;
  final String msg;
  final bool isError;

  ProgressEvent({
    required this.type,
    required this.msg,
    this.isError = false,
  });

  @override
  String toString() => '${time.toIso8601String()}'
      ' | $type'
      ' ${isError ? ' | ERROR' : ''}'
      ' | $msg';
}
abstract interface class ProgressPublisher {
  Stream<ProgressEvent> subscribeProgress();
  addProgress(ProgressEvent pe);
}
