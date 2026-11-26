Feature: Message text
  Text from outside the process is shown in an exception message as one bounded line,
  and the set of characters that must be escaped is one predicate that both
  `clipForMessage` and any other package use.

  Scenario: A control character is escaped and the message stays on one line
    Given text from outside the process that holds a line break or another control, format or line-separator character
    When it is clipped for an exception message
    Then each such character, and each backslash, is shown as an escape and the message stays on one line

  Scenario: The shared message-text predicate classifies each range end as its escape does
    Given the characters at and beside each end of each escaped range
    When the shared predicate is asked
    Then it answers escaped exactly where clipForMessage writes an escape

  Scenario: Text is clipped at the bound without cutting an escape
    Given text longer than the message bound that ends in an escape
    When it is clipped
    Then at most the bound is kept, no escape is cut, and a marker says text was left out
