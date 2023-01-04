class ObjectLifeCycleOptions {
  // How long the object is supposed to live
  Duration? timeToLive;

  // when the object becomes available
  Duration? timeToBirth;

  /// If set to true, delete operation will delete recipient's  cached key also
  bool? cascadeDelete;

  Duration? cacheRefreshIntervalOnRecipient;

  ObjectLifeCycleOptions(
      {this.timeToBirth,
      this.timeToLive,
      this.cascadeDelete,
      this.cacheRefreshIntervalOnRecipient});
}
