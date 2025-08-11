import 'package:at_server_status/at_server_status.dart';

class Strings {
  static const String Followers = 'Followers';
  static const String Following = 'Following';
  static const String Follow = 'Follow';
  static const String Unfollow = 'Unfollow';
  static const String BackButton = 'Back';
  static const String Title = 'Connections';
  static const String Search = 'Filter @signs';
  static const String Error = 'Error';
  static const String Close = 'Close';
  static const String atsign = '@';
  static const String package = 'at_follows_flutter';
  static const String noFollowers = 'No Followers!';
  static const String noFollowing = 'You are not following anyone!';
  static const String invalidAtsign = 'Invalid Atsign';

  //public content
  static const String publicContentAppbarTitle = 'Public Content';
  static String? directoryUrl;
  static String? rootdomain;

  static const String privateFollowersList =
      'Public cannot see your followers list when it’s set to private';
  static const String privateFollowingList =
      'Public cannot see your following list when it’s set to private';
  static const List<String> publicDataKeys = [
    'firstname.persona',
    'lastname.persona',
    'image.persona'
  ];

  //follow texts
  static const String followBack = 'Follow Back';
  static const String cancel = 'Cancel';
  static String followBackDescription(String? atsign) {
    return '$atsign is following you. Tap on follow back to get connected.';
  }

  static const String followDescription = 'Do you want to follow ';

  //qrscan texts
  static const String enterAtsignButton = 'Type the @sign';
  static const String enterAtsignTitle = 'Enter the @sign';
  static const String atsignHintText = 'alice';
  static const String qrTitle = 'Follow @sign';
  static const String qrscanDescription =
      'Toggle to scan the QR code of an @sign to follow';
  static const String submitButton = 'Submit';
  static const String existingFollower = 'You are already following ';
  static const String ownAtsign = 'You cannot follow your own @sign';
  static const String invalidAtsignMessage =
      'Please provide or scan a valid @sign to follow';
  // static const String atSignStatusMessage = 'This @sing is unreachable. P'
  static String getAtSignStatusMessage(AtSignStatus? status) {
    status ??= AtSignStatus.error;
    switch (status) {
      case AtSignStatus.unavailable:
      case AtSignStatus.notFound:
        return '@sign is not registered yet. Please try with the registered one.';
      case AtSignStatus.error:
        return '@sign and the server is unreachable. Please try again';
      default:
        return 'Unknown status. Please try again later.';
    }
  }

  //error dialog texts
  static const String errorTitle = 'Error';
  static const String closeButton = 'Close';

  //loading texts
  static const String loadingDescription =
      'Please wait while loading your data';
}
