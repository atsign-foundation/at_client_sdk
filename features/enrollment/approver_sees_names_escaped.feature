Feature: An approver sees the names a request carries with their control characters escaped

  at_activate's list, approve and auto show the app name, device name and
  namespaces an enrollment request carries, as the atServer serves them or
  a notification announces them, with each control, format or
  line-separator character escaped, ESC as \u001b, and each clipped after
  180 characters, followed by "...". A list row stays on one line, its
  columns padded after escaping. approve and auto name the app and device
  in double quotes, with a quote inside escaped. A request's id and status,
  and the key an Anchored verdict names, are escaped and clipped the same
  way, and so are the key of a notification auto ignores or cannot act on
  and the error that stopped it; auto names the sender of a notification
  from another atSign in double quotes.

  Races and replay: none arises; escaping is a pure function of text already
  read, and nothing new is sent.
  DoS: each name shown is clipped at 180 characters; how many requests a
  listing holds, and how many namespaces each asks for, is the atServer's
  to bound.
  Forgery and impersonation: the names are the ones the requesting device
  filed, as the approver's own atServer serves them; shown escaped, a name
  cannot pass for another line or another row of the output. A notification
  from another atSign is not acted on, and the warning naming it shows its
  key and sender escaped.

  Scenario Outline: at_activate list shows a request's <field> with its control characters escaped
    Given @alice's atServer holding a pending enrollment request whose <field> holds a <char>
    When at_activate list runs for @alice
    Then that request's row shows the <char> written as <escape>, and every line the list prints ends where a row ends
    And each column after it starts where the header's does
    Examples:
      | field       | char            | escape |
      | app name    | carriage return | \u000d |
      | device name | ESC             | \u001b |
      | namespace   | line feed       | \u000a |

  Scenario Outline: <command> names the request's app and device in double quotes, escaped
    Given a pending enrollment request for @alice whose app name is "wa<ESC>vi" and whose device name is "pho<CR>ne"
    When <command> handles that request
    Then what it prints names them as "wa\u001bvi" and "pho\u000dne"
    Examples:
      | command             |
      | at_activate approve |
      | at_activate auto    |

  Scenario Outline: <command> escapes a double quote inside the app and device names it quotes
    Given a pending enrollment request for @alice whose app name is wa"vi and whose device name is pho"ne
    When <command> handles that request
    Then what it prints names them as "wa\"vi" and "pho\"ne"
    Examples:
      | command             |
      | at_activate approve |
      | at_activate auto    |

  Scenario: at_activate list clips a name longer than 180 characters
    Given @alice's atServer holding a pending enrollment request whose device name is 400 characters long
    When at_activate list runs for @alice
    Then that request's row shows the device name's first characters followed by "...", 180 characters before the "..."

  Scenario: at_activate list shows the key an Anchored verdict names with its control characters escaped
    Given @alice's atServer holding an approved enrollment whose _apsk record lists its client data signing key under a kid holding a line feed, and the key fails the anchoring check
    When at_activate list runs for @alice
    Then that enrollment's Anchored column shows the line feed written as \u000a, and every line the list prints ends where a row ends

  Scenario: at_activate auto escapes the key and sender of a notification from another atSign
    Given at_activate auto running for @alice
    When a notification from @bob arrives whose key holds an ESC and ends .new.enrollments.__manage
    Then the warning naming the sender and the key shows them on one line, the ESC written as \u001b and the sender in double quotes, and auto does not act on it
