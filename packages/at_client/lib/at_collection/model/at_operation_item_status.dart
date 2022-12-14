class AtOperationItemStatus {
  late String atSign;
  late String key;
  bool? complete;
  Exception? exception;

  AtOperationItemStatus({
    required this.atSign,
    required this.key,
    required this.complete,
    this.exception,
  });
}
