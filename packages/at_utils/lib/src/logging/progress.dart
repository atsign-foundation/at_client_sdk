class ProgressEvent {
  DateTime time;
  String type;
  String msg;
  bool isError;

  ProgressEvent(this.time, this.type, this.msg, this.isError);

  @override
  String toString() => '${time.toIso8601String()}'
      ' | $type'
      ' ${isError ? ' | ERROR' : ''}'
      ' | $msg';
}
abstract interface class ProgressListener {
  Stream<ProgressEvent> subscribeProgress();
  addProgress(ProgressEvent pe);
}
