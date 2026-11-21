Feature: An approver sees the names a request carries with their control characters escaped

  at_activate's list, approve and auto_approve show the app name, device
  name and namespaces an enrollment request carries, as the atServer serves
  them or a notification announces them, with each control, format or
  line-separator character escaped, ESC as \u001b, and each clipped after
  180 characters, followed by "...". A list row stays on one line, its
  columns padded after escaping. approve and auto_approve name the app and
  device in double quotes, with a quote inside escaped.

  Races and replay: none arises; escaping is a pure function of text already
  read, and nothing new is sent.
  DoS: each name shown is clipped at 180 characters; how many requests a
  listing holds, and how many namespaces each asks for, is the atServer's
  to bound.
  Forgery and impersonation: the names are the ones the requesting device
  filed, as the approver's own atServer serves them; shown escaped, a name
  cannot pass for another line or another row of the output.

  Scenario Outline: at_activate list shows a request's <field> with its control characters escaped
    Given @alice's atServer holding a pending enrollment request whose <field> holds a <char>
    When at_activate list runs for @alice
    Then that request's row shows the <char> written as <escape>, and every line the list prints ends where a row ends
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
      | command                 |
      | at_activate approve     |
      | at_activate auto-approve |

  Scenario Outline: <command> escapes a double quote inside the app name it quotes
    Given a pending enrollment request for @alice whose app name is wa"vi
    When <command> handles that request
    Then what it prints names the app as "wa\"vi"
    Examples:
      | command             |
      | at_activate approve |
      | at_activate auto    |

  Scenario: at_activate list clips a name longer than 180 characters
    Given @alice's atServer holding a pending enrollment request whose device name is 400 characters long
    When at_activate list runs for @alice
    Then that request's row shows the device name's first characters followed by "...", 180 characters before the "..."
