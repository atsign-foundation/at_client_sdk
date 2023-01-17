class ObjectLifeCycleOptions {
  // How long the object is supposed to live
  Duration? timeToLive;

  // when the object becomes available
  Duration? timeToBirth;

  /// If set to true, delete operation will delete recipient's  cached key also
  bool cascadeDelete;

  Duration cacheRefreshIntervalOnRecipient;

  bool cacheValueOnRecipient;

  ObjectLifeCycleOptions(
      {this.timeToBirth,
      this.timeToLive,
      this.cascadeDelete = true,
      this.cacheValueOnRecipient = true,
      this.cacheRefreshIntervalOnRecipient = const Duration(days: 5)});
}
