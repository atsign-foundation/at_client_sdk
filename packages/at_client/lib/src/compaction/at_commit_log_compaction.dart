import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_logger.dart';

/// The class responsible to compact the commit log at a frequent time interval.
///
/// The call to [create] method will return an instance of [AtClientCommitLogCompaction].
///
/// Implements to [AtSignChangeListener] to get notified on switch atSign event. On switch atSign event,
/// pause's the compaction job on currentAtSign and start/resume the compaction job on the new atSign
///
/// The call to [scheduleCompaction] will initiate the commit log compaction. The method
/// accepts an integer which represents the time interval in minutes.
///
/// The call to [getCompactionStats] will returns the metric of the previously run compaction
/// job.
class AtClientCommitLogCompaction {
  late AtCompactionJob _atCompactionJob;

  late final AtSignLogger _logger;

  /// A static builder method to return an instance of [AtClientCommitLogCompaction]
  ///
  /// Accepts AtClientManager, currentAtSign and [AtCompactionJob]. Inserts the [AtCompactionJob]
  /// against the respective currentAtSign in the [_atCompactionJobMap] and returns an
  /// instance of [AtClientCommitLogCompaction].
  ///
  /// Register's to [AtSignChangeListener.listenToAtSignChange] to pause the compaction job on currentAtSign
  /// and start/resume the compaction job on the new atSign
  static AtClientCommitLogCompaction create(
      String currentAtSign, AtCompactionJob atCompactionJob) {
    AtClientCommitLogCompaction atClientCommitLogCompaction =
        AtClientCommitLogCompaction._(currentAtSign, atCompactionJob);
    return atClientCommitLogCompaction;
  }

  AtClientCommitLogCompaction._(
      String currentAtSign, AtCompactionJob atCompactionJob) {
    _atCompactionJob = atCompactionJob;
    _logger = AtSignLogger('AtClientCommitLogCompaction ($currentAtSign)');
  }

  /// The call to [scheduleCompaction] will initiate the commit log compaction. The method
  /// accepts an integer which represents the time interval in minutes.
  void scheduleCompaction(int timeIntervalInMins) {
    _logger.info('Starting commit log compaction job');
    var atClientCommitLogCompaction = AtCompactionConfig()
      ..compactionFrequencyInMins = timeIntervalInMins;
    _atCompactionJob.scheduleCompactionJob(atClientCommitLogCompaction);
  }

  Future<void> stopCompactionJob() async {
    _logger.info('Stopping commit log compaction job');
    await _atCompactionJob.stopCompactionJob();
  }
}
