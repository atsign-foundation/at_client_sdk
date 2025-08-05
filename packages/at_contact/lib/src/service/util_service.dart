import 'package:intl/intl.dart';

class UtilServices {
  static final UtilServices _singleton = UtilServices._internal();
  static DateFormat dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  // AtSignLogger _logger = AtSignLogger("UtilServices");

  UtilServices._internal();

  factory UtilServices() {
    return _singleton;
  }

  static String dateToString(DateTime date) {
    return dateFormat.format(date);
  }

  static DateTime stringToDate(String date) {
    return dateFormat.parse(date);
  }
}
