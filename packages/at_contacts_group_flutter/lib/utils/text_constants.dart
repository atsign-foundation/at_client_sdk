class TextConstants {
  TextConstants._();
  static final TextConstants _instance = TextConstants._();
  factory TextConstants() => _instance;

  // ignore: non_constant_identifier_names
  String SERVICE_ERROR = 'something went wrong, please try again.';
  // ignore: non_constant_identifier_names
  String GROUP_ALREADY_EXISTS = 'group with this name already exists';
  // ignore: non_constant_identifier_names
  String GROUP_PRESENT =
      'a group with this name already exists, try another name';
  // ignore: non_constant_identifier_names
  String INVALID_NAME = 'enter a valid name';
  // ignore: non_constant_identifier_names
  String EMPTY_NAME = 'add a group name';
  // ignore: non_constant_identifier_names
  String MEMBER_ADDED = 'member added';
  // ignore: non_constant_identifier_names
  String GROUP_NAME_REGEX =
      r'[\u0020\u0009\u000A\u000B\u000C\u000D\u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000]';

  /// Sibebar width
  // ignore: constant_identifier_names
  static const double SIDEBAR_WIDTH = 70;
}
