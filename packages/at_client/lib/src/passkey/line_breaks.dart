/// Throws [ArgumentError], naming [name], when [value] holds a carriage
/// return or a line feed: a command line carries the value, so a line break
/// would end it early.
void refuseLineBreaks(String value, String name) {
  if (value.contains('\r') || value.contains('\n')) {
    throw ArgumentError.value(value, name, 'must not contain newlines');
  }
}
