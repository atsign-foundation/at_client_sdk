import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_follows_flutter/domain/at_follows_list.dart';
import 'package:at_follows_flutter/domain/connection_model.dart';
import 'package:at_follows_flutter/services/connections_service.dart';
import 'package:at_follows_flutter/services/sdk_service.dart';

class AtFollowServices {
  AtFollowServices._();
  static final AtFollowServices _instance = AtFollowServices._();
  factory AtFollowServices() => _instance;
  bool isDataFetched = false;
  var _connectionService = ConnectionsService();
  ConnectionProvider _connectionProvider = ConnectionProvider();

  Future initializeFollowService(AtAuthService atClientserviceInstance) async {
    _connectionService
        .init(AtClientManager.getInstance().atClient.getCurrentAtSign()!);
    _connectionProvider
        .init(AtClientManager.getInstance().atClient.getCurrentAtSign()!);
    SDKService().setClientService = atClientserviceInstance;
    await _connectionService.getAtsignsList(isInit: true);
    _connectionService.startMonitor();
  }

  ConnectionsService get connectionService => _connectionService;

  ConnectionProvider get connectionProvider => _connectionProvider;
  // method to get followers list
  AtFollowsList? getFollowersList() {
    return _connectionService.followers;
  }

  // method to get following list
  AtFollowsList? getFollowingList() {
    return _connectionService.following;
  }

  // method to unfollow an atsign
  Future unfollow(String atsign) async {
    return await _connectionProvider.unfollow(atsign);
  }

  // method to follow an atsign
  Future follow(String atsign) async {
    return await _connectionProvider.follow(atsign);
  }

  // method to remove follwer
  Future<bool> removeFollower(String atsign) async {
    return await _connectionService.removeFollower(atsign);
  }
}
