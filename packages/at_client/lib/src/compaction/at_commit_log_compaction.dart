import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
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
class AtClientCommitLogCompaction implements AtSignChangeListener {
  static final Map<String, AtClientCommitLogCompaction>
      atClientCommitLogCompactionMap = {};

  AtCompactionConfig atCompactionConfig = AtCompactionConfig();

  final AtCompactionStats _atCompactionStats = AtCompactionStats();

  late AtCompactionJob _atCompactionJob;

  late SecondaryKeyStore secondaryKeyStore;

  late String _currentAtSign;

  final _logger = AtSignLogger('AtClientCommitLogCompaction');

  /// A static builder method to return an instance of [AtClientCommitLogCompaction]
  ///
  /// Accepts AtClientManager, currentAtSign and [AtCompactionJob]. Inserts the [AtCompactionJob]
  /// against the respective currentAtSign in the [_atCompactionJobMap] and returns an
  /// instance of [AtClientCommitLogCompaction].
  ///
  /// Register's to [AtSignChangeListener.listenToAtSignChange] to pause the compaction job on currentAtSign
  /// and start/resume the compaction job on the new atSign
  static AtClientCommitLogCompaction create(
      AtClientManager atClientManager, AtCompactionJob atCompactionJob) {
    String atSign = atClientManager.atClient.getCurrentAtSign()!;
    if (atClientCommitLogCompactionMap.containsKey(atSign)) {
      return atClientCommitLogCompactionMap[atSign]!;
    }
    AtClientCommitLogCompaction atClientCommitLogCompaction =
        AtClientCommitLogCompaction._(atCompactionJob, atSign);
    atClientManager.listenToAtSignChange(atClientCommitLogCompaction);
    atClientCommitLogCompactionMap.putIfAbsent(
        atSign, () => atClientCommitLogCompaction);
    return atClientCommitLogCompaction;
  }

  AtClientCommitLogCompaction._(
      AtCompactionJob atCompactionJob, String currentAtSign) {
    _atCompactionJob = atCompactionJob;
    _currentAtSign = currentAtSign;
  }

  /// The call to [scheduleCompaction] will initiate the commit log compaction. The method
  /// accepts an integer which represents the time interval in minutes.
  void scheduleCompaction(int timeIntervalInMins, String currentAtSign) {
    _logger.info('Starting commit log compaction job for $currentAtSign');
    var atClientCommitLogCompaction = atCompactionConfig
      ..compactionFrequencyInMins = timeIntervalInMins;
    _atCompactionJob.scheduleCompactionJob(atClientCommitLogCompaction);
  }

  /// The call to [getCompactionStats] will returns the metric of the previously run compaction
  /// job.
  ///
  /// Fetches the commit log compaction metrics and converts it into an [AtCompactionStats] object
  /// and returns the object.
  ///
  /// When the key is not available, returns [DefaultCompactionStats.getDefaultCompactionStats]
  Future<AtCompactionStats> getCompactionStats() async {
    if (!secondaryKeyStore.isKeyExists(commitLogCompactionKey)) {
      return _atCompactionStats.getDefaultCompactionStats();
    }
    AtData atData = await secondaryKeyStore.get(commitLogCompactionKey);
    var decodedCommitLogCompactionStatsJson = jsonDecode(atData.data!);
    var atCompactionStats = _atCompactionStats
      ..atCompactionType = decodedCommitLogCompactionStatsJson[
          AtCompactionConstants.atCompactionType]
      ..preCompactionEntriesCount = int.parse(
          decodedCommitLogCompactionStatsJson[
              AtCompactionConstants.preCompactionEntriesCount])
      ..postCompactionEntriesCount = int.parse(
          decodedCommitLogCompactionStatsJson[
              AtCompactionConstants.postCompactionEntriesCount])
      ..lastCompactionRun = DateTime.parse(decodedCommitLogCompactionStatsJson[
          AtCompactionConstants.lastCompactionRun])
      ..deletedKeysCount = int.parse(decodedCommitLogCompactionStatsJson[
          AtCompactionConstants.deletedKeysCount])
      ..compactionDurationInMills = int.parse(
          decodedCommitLogCompactionStatsJson[
              AtCompactionConstants.compactionDurationInMills]);
    return atCompactionStats;
  }

  @override
  void listenToAtSignChange(SwitchAtSignEvent switchAtSignEvent) {
    if (switchAtSignEvent.previousAtClient?.getCurrentAtSign() ==
        _currentAtSign) {
      _logger.info(
          'Stopping commit log compaction job for ${switchAtSignEvent.previousAtClient?.getCurrentAtSign()}');
      AtClientCommitLogCompaction atClientCommitLogCompaction =
          atClientCommitLogCompactionMap[
              switchAtSignEvent.previousAtClient?.getCurrentAtSign()]!;
      atClientCommitLogCompaction._atCompactionJob.stopCompactionJob();
      atClientCommitLogCompactionMap
          .remove(switchAtSignEvent.previousAtClient?.getCurrentAtSign());
    }
  }
}

/// An extension class on AtCompactionStats for the default compaction stats on client commit log
/// when the [commitLogCompactionKey] is not available
extension DefaultCompactionStats on AtCompactionStats {
  getDefaultCompactionStats() {
    return AtCompactionStats()
      ..atCompactionType = 'AtCommitLog'
      ..compactionDurationInMills = -1
      ..preCompactionEntriesCount = -1
      ..postCompactionEntriesCount = -1
      ..deletedKeysCount = -1
      ..lastCompactionRun = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
