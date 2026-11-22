Feature: A keyfile date that does not parse is named without its value

  Races: none; a read parses one snapshot. Replay: none; nothing is sent.
  DoS: the message is fixed-size whatever the field's size. Forgery and
  impersonation: unchanged; what open does with keys it cannot read is
  decided separately.

  Scenario: A date field that does not parse names the field and none of its value
    Given an atKeys document whose createdAt holds a value that is not a date
    When AtKeys.fromJson reads it
    Then it throws AtKeysParseException naming createdAt and the parser's reason, holding none of the field's value
