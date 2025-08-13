// ignore_for_file: non_constant_identifier_names

class AllText {
  AllText._();
  static final AllText _instance = AllText._();
  factory AllText() => _instance;

  String APP_NAME = '@location';
  String CANCEL = 'Cancel';
  String CLOSE = 'Close';

  // notification
  String MSG_NOTIFY = 'msgNotify';
  String LOCATION_NOTIFY = 'locationotify';
  String EVENT_NOTIFY = 'eventnotify';

  String LOC_START_TIME_TITLE =
      'When do you want to start sharing your location?';
  String LOC_END_TIME_TITLE =
      'When do you want your location to be turned off ?';

  // Event Collapsed Content
  String EDIT = 'Edit';
  String AND = 'and';
  String MORE = 'more';
  String SHARE_MY_LOCATION_FROM = 'Share my location from';
  String ON = 'On';
  String PEOPLE = 'people';
  String PERSON = 'person';
  String SEE_PARTICIPANTS = 'See Participants';
  String ADDRESS = 'Address: ';
  String SHARE_LOCATION = 'Share Location';
  String EVENT_CANCELLED = 'Event cancelled';
  String EVENT_EXITED = 'Event exited';
  String UPDATING_DATA = 'Updating data';
  String SOMETHING_WENT_WRONG_TRY_AGAIN =
      'Something went wrong , please try again.';
  String DO_YOU_WANT_TO_EXIT = 'Do you want to exit';
  String DO_YOU_WANT_TO_CANCEL = 'Do you want to cancel';
  String EXITED = 'Exited';
  String ACCEPTED = 'Accepted';
  String EXIT_EVENT = 'Exit Event';
  String CANCEL_EVENT = 'Cancel Event';
  String CANCELLING = 'Cancelling';
  String EXITING = 'Exiting';

  // Participants
  String PARTICIPANTS = 'Participants';
  String LOC_NOT_RECIEVED = 'Location not received';
  String ACTION_REQUIRED = 'Action Required';

  // Notification Dialog
  String SHARE_EVENT_DES =
      'wants to share an event with you. Are you sure you want to join and share your location with the group?';
  String PER_INVITED = 'person invited';
  String PEP_INVITED = 'people invited';
  String EVENT_RUNNING_DES =
      'You already have an event scheduled during this hour. Are you sure you want to accept another?';
  String REQ_TO_UPDATE_DATA_SUB = 'Request to update data is submitted';
  String YES = 'Yes';
  String NO = 'No';

  // Create Event
  String SOMETHING_WENT_WRONG = 'Something went wrong';
  String EVENT_UPDATED = 'Event updated';
  String EVENT_ADDED = 'Event Added';
  String SAVE = 'Save';
  String CREATE_AND_INVITE = 'Create & Invite';
  String ENDS_AFTER = 'Ends after';
  String OCCURENCE = 'occurrence';
  String REPEATS_EVERY = 'Repeats every ';
  String WEEK_ON = 'week on';
  String DAY = 'day';
  String MONTH_ON = 'month on';
  String TO = ' to';
  String EVENT_TODAY = 'Event today ';
  String EVENT_ON = 'Event on';
  String SELECT_TIMES = 'Select Times';
  String START_TYPING_OR_SEL_FRM_MAP = 'Start typing or select from map';
  String ADD_VENUE = 'Add Venue';
  String TITLE_OF_THE_EVENT = 'Title of the event';
  String TITLE = 'Title';
  String SELECT_AT_SIGN_FROM_CONTACT = 'Select atSign from contacts';
  String SEND = 'Send To';
  String CREATE_EVENT = 'Create an event';

  // ONE DAY EVENT
  String ONE_DAY_EVENT = 'One Day Event';
  String SELECT_DATE = 'Select Date';
  String SELECT_START_DATE = 'Select Start Date';
  String SELECT_END_DATE = 'Select End Date';
  String SELECT_TIME = 'Select Time';
  String START = 'Start';
  String STOP = 'Stop';
  String SELECT_START_TIME_FIRST = 'Select start time first';
  String DONE = 'DONE';

  // Recurring Event
  String RECURRING_EVENT = 'Recurring event';
  String REPEAT_EVERY = 'Repeat every';
  String REPEAT_CYCLE = 'repeat cycle';
  String WEEK = 'Week';
  String MONTH = 'Month';
  String SELECT_CATEGORY = 'Select Category';
  String OCCURS_ON = 'Occurs on';
  String ENDS_ON = 'Ends On';
  String NEVER = 'Never';
  String AFTER = 'After';

  // Select Location
  String SEARCH_AN_AREA_STREET_NAME = 'Search an area, street name…';
  String GETTING_LOCATION_PERMISSION = 'Getting location permission';
  String UNABLE_TO_ACCESS_LOCATION = 'Unable to access location';
  String NEAR_ME = 'Near me';
  String CANNOT_ACCESS_LOCATION_PERMISSION =
      '(Location disabled. In order to use this feature, please go to your settings and allow @rrive to access your location.)';
  String CURRENT_LOCATION = 'Current Location';
  String USING_GPS = 'Using GPS';
  String NO_SUCH_LOCATION_FOUND = 'No such location found';
  String YOUR_LOCATION = 'Your location';
  String PAST_VENUES = 'Select from past venues';

  // Selected Location
  String LABEL = 'Label';
  String SAVE_THIS_ADDRESS_AS = 'Save this address as';
  String CANNOT_LEAVE_LABEL_EMPTY = 'Cannot leave LABEL empty';

  // Concurrent Event Request Dialog
  String YES_CREATE_ANOTHER = 'Yes! Create another';
  String NO_CANCEL_THIS = 'No! Cancel this';

  // Display Tile
  String REQ_DECLINED = 'Request declined';
  String CANCELLED = 'Cancelled';
  String RETRY = 'Retry';

  // Invite Card
  String DECIDE_LATER = 'Decide Later';

  // Overlapping Contacts
  String OTHER = 'other';
  String OTHERS = 'others';
}
