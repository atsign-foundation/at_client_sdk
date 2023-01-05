class AtOperationItemStatus {
  late String atSign;
  late String key;
  bool complete;
  Exception? exception;
  Operation? operation;

  AtOperationItemStatus({
    required this.atSign,
    required this.key,
    required this.complete,
    required this.operation,
    this.exception,
  });
}

enum Operation { save, share, unshare, delete }
