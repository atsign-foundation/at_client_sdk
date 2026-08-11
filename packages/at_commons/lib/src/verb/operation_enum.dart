enum OperationEnum { update, delete, append, remove }

String getOperationName(OperationEnum? d) => '$d'.split('.').last;

enum PriorityEnum { low, medium, high }

String getPriority(PriorityEnum? priorityEnum) =>
    '$priorityEnum'.split('.').last;

enum StrategyEnum { all, latest }

String getStrategy(StrategyEnum? strategyEnum) =>
    '$strategyEnum'.split('.').last;

enum MessageTypeEnum {
  key,
  @Deprecated('text based notifications are deprecated')
  text,
}

String getMessageType(MessageTypeEnum? messageTypeEnum) =>
    '$messageTypeEnum'.split('.').last;

enum EnrollOperationEnum {
  request,
  approve,
  deny,
  revoke,
  list,
  fetch,
  unrevoke,
  delete,

  /// An approved enrollment amending its own record: `apkamPublicKey`,
  /// `signingAlgo`, `apsk` and `metadata`. Self-only — the connection's
  /// enrollment id must equal the target's — and it never reaches
  /// `namespaces` or the approval state, because an operation an enrollment
  /// can invoke on itself must not be able to widen its own grant.
  update
}

String getEnrollOperation(EnrollOperationEnum? enrollOperationEnum) =>
    '$enrollOperationEnum'.split('.').last;
