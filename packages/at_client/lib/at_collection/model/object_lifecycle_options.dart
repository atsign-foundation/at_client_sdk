class ObjectLifeCycleOptions {
  // How long the object is supposed to live
  Duration? timeToLive;

  // when the object becomes available
  Duration? timeToBirth;

  ObjectLifeCycleOptions(
    {this.timeToBirth, this.timeToLive}
  );
}