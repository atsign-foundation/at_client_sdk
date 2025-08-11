// ignore_for_file: non_constant_identifier_names

class AllText {
  AllText._();
  static final AllText _instance = AllText._();
  factory AllText() => _instance;

  // HomeScreen
  String SOMETHING_WENT_WRONG = 'Something went wrong!!';
  String NO_DATA_FOUND = 'No Data Found!!';
  String REQUEST_LOCATION = 'Request Location';
  String SHARE_LOCATION = 'Share Location';

  // Notification Dialog
  String ACCEPT_SHARE_LOCATION =
      'wants to share their location with you. Are you sure you want to accept their location?';
  String SHARE_YOUR_LOCATION =
      'wants you to share your location. Are you sure you want to share?';
  String YES = 'Yes';
  String NO = 'No';
  String HOW_LONG_DO_YOU_WANT_SHARE_YOUR_LOCATION =
      'How long do you want to share your location for ?';
  String untilTurnedOff = 'Until turned off';
  String k30mins = '30 mins';
  String k2hours = '2 hours';
  String k24hours = '24 hours';
  String DECIDE_LATER = 'Decide Later';

  // Request Location Sheet
  String CANCEL = 'Cancel';
  String REQUEST_FROM = 'Request From';
  String TYPE_AT_SIGN = 'Type atSign ';
  String REQUEST = 'Request';
  String AT_SIGN_NOT_VALID = 'Atsign not valid';
  String REQUEST_LOCATION_SENT = 'Request Location sent';
  String SOMETHING_WENT_WRONG_TRY_AGAIN = 'Some thing went wrong , try again.';

  // Share Location Sheet
  String SHARE_WITH = 'Share with';
  String DURATION = 'Duration';
  String OCCURS_ON = 'Occurs on';
  String SHARE = 'Share';
  String SELECT_TIME = 'Select time';
  String SHARE_LOC_REQ_SENT = 'Share Location Request sent';

  // Collapsed Content
  String PER_NOT_SHARING_LOC =
      'This person is not currently sharing their location with you';
  String SHARING_LOCATION = 'Sharing their location';
  String LOC_SHARING_TURNED_OFF = "This user's location sharing is turned off";
  String SHARING_MY_LOC = 'Sharing my location';
  String SHARE_MY_LOC = 'Share my Location';
  String REMOVE_PERSON = 'Remove Person';
  String DO_YOU_WANT_TO_REMOVE = 'Do you want to remove';
  String SEE_PARTICIPANTS = 'See Participants';

  // Display Tile
  String ACTION_REQUIRED = 'Action required';
  String REQUEST_DECLINED = 'Request declined';
  String CANCELLED = 'Cancelled';
  String RETRY = 'Retry';

  // Location Promt Dialog
  String OKAY = 'Okay!';
  String UPDATE_CANCELLED = 'Update cancelled';
  String PROMPT_CANCELLED = 'Prompt cancelled';
  String SHARE_LOC_REQ_SENT_TO = 'Share Location Request sent to ';
  String SOMETHING_WENT_WRONG_FOR = 'Something went wrong for ';
  String PROMPTED_AGAIN_TO = 'Prompted again to ';

  // Marker Cluster
  String PERSON_NEAR_BY = 'person nearby';
  String PEOPLE_NEAR_BY = 'people nearby';
}
