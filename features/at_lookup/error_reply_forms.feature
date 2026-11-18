Feature: A lookup reads an atServer's error reply as its code, in every form

  An atServer writes an error reply as error:<code>-<text>,
  error:<code>:<text>, or error:{"errorCode":"<code>","errorDescription":"<text>"}.
  A lookup takes the code and the text after it from each form, so whoever
  handles the exception sees the code the atServer sent.

  Races: none arise; one reply is read where it arrived.
  Replay: none arise; an error reply carries no secret and no freshness.
  DoS: the reply is already read and bounded; taking its code is one match,
       or one anchored match where a JSON reply is cut short.
  Forgery and impersonation: the reply comes from the client's own atServer
  over its TLS connection; taking the code it wrote grants nothing.

  Scenario: A colon-form reply is read as its code
    Given an atServer that answers a verb with error:AT0027:The enrollment id: 9821c174-cd2a-4a96-b3a9-ea4eb8e13db9 is revoked
    When a lookup executes that verb
    Then it throws an AtLookUpException with code AT0027 and the text after the colon

  Scenario: A dash-form or JSON reply is read as its code
    Given an atServer that answers a verb with error:AT0015-key not found, or with the same code and text as JSON
    When a lookup executes that verb
    Then it throws an AtLookUpException with code AT0015 and text "key not found"

  Scenario: A reply with no code at its head is an unknown error
    Given an atServer that answers a verb with an error: reply that does not start with a code
    When a lookup executes that verb
    Then it throws an AtLookUpException with code AT0014 whose text holds the reply

  Scenario: A code is read only where a dash, a colon or the end of the reply follows it
    Given a message holding error:AT00271-x, or error:AT0027 followed by a space, or error:AT0027 alone
    When the code in the message is read
    Then the first two read as no code, and the last reads as AT0027

  Scenario: A JSON reply followed by other text is read as its code
    Given a message holding error:{"errorCode":"AT0401","errorDescription":"x"} and then other text
    When the code in the message is read
    Then it reads as AT0401, and a code that appears only in an errorDescription, or with no string errorCode, is never read
