class AppConstants {
  static final String following = 'at_following_by_self';
  static final String followers = 'at_followers_of_self';
  static final String publicImage = 'image.persona';
  static final String publicFirstname = 'firstname.persona';
  static final String publicLastname = 'lastname.persona';
  static final String libraryNamespace = 'at_follows';
  static final String followingKey = 'following_by_self.$libraryNamespace';
  static final String followersKey = 'followers_of_self.$libraryNamespace';
  static final String containsFollowing = 'following_by_self';
  static final String containsFollowers = 'followers_of_self';
  static String appUrl = 'atprotocol://persona';

  static const int responseTimeLimit = 30;
}
