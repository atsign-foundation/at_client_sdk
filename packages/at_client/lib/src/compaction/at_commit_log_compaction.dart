import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_logger.dart';

/// The class responsible to compact the commit log at a frequent time interval.
///
/// The call to [create] method will return an instance of [AtClientCommitLogCompaction].
///
/// The call to [scheduleCompaction] will initiate the commit log compaction. The method
/// accepts an integer which represents the time interval in minutes.
///
/// The call to [stopCompactionJob] will stop the compaction job
class AtClientCommitLogCompaction {
  late AtCompactionJob _atCompactionJob;

  late final AtSignLogger _logger;

  /// A static builder method to return an instance of [AtClientCommitLogCompaction]
  ///
  /// Accepts currentAtSign and [AtCompactionJob].
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
    _logger.info(
        'Starting commit log compaction job running for every $timeIntervalInMins minute(s)');
    var atClientCommitLogCompaction = AtCompactionConfig()
      ..compactionFrequencyInMins = timeIntervalInMins;
    _atCompactionJob.scheduleCompactionJob(atClientCommitLogCompaction);
  }

  /// Delegates the call to [AtCompactionJob.stopCompactionJob] to stop the compaction job.
  Future<void> stopCompactionJob() async {
    _logger.info('Stopping commit log compaction job');
    await _atCompactionJob.stopCompactionJob();
  }

  /// Returns true if the compaction job is running, else returns false.
  bool isCompactionJobRunning() {
    return _atCompactionJob.isScheduled();
  }
}
