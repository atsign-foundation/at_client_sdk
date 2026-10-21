/// Why [what] did not parse as JSON, from the parser's [e]: its reason and
/// the 1-based character where it stopped, and none of the text it parsed.
String notValidJson(String what, FormatException e) {
  final offset = e.offset;
  return '$what is not valid JSON: ${e.message}'
      '${offset == null ? '' : ' (at character ${offset + 1})'}';
}
