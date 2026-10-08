// OpenTelemetry log severity levels, numbered 1 to 24 by the OTel logs data
// model. Larger numbers are more severe.
enum AtTelemetrySeverity {
  trace(1),
  trace2(2),
  trace3(3),
  trace4(4),
  debug(5),
  debug2(6),
  debug3(7),
  debug4(8),
  info(9),
  info2(10),
  info3(11),
  info4(12),
  warn(13),
  warn2(14),
  warn3(15),
  warn4(16),
  error(17),
  error2(18),
  error3(19),
  error4(20),
  fatal(21),
  fatal2(22),
  fatal3(23),
  fatal4(24);

  final int number;

  const AtTelemetrySeverity(this.number);

  // The OTel short name, for example INFO or ERROR2
  String get shortName => name.toUpperCase();

  // Returns null for 0 (unspecified) or any number outside 1 to 24
  static AtTelemetrySeverity? fromNumber(int number) {
    if (number < 1 || number > values.length) {
      return null;
    }
    return values[number - 1];
  }
}
