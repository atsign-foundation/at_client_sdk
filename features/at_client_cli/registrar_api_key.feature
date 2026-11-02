# Amended 2026-11-02 by Gary's choice: at_register and at_activate keep a
# built-in registrar API key, as in 3.x, and AT_REGISTRAR_API_KEY, when set,
# replaces it. Each amended line below says what it used to say.
Feature: at_register and at_activate send the registrar API key from the environment, or a built-in one

  # Was: "at_register and at_activate take the registrar API key from the
  # environment".
  The registrar API key names the app to the registrar. at_register and
  at_activate send AT_REGISTRAR_API_KEY when it is set, and otherwise a key
  built into at_client_cli. An app developer may create a key of their own
  via the registrar at my.atsign.com.
  # Was: "at_client_cli carries none: an app developer creates one via the
  # registrar at my.atsign.com and sets AT_REGISTRAR_API_KEY."

  Races, replay: none arise.
  DoS: every run without AT_REGISTRAR_API_KEY names the same built-in key to
  the registrar; a key that is set but unusable sends nothing.
  # Was: "DoS: with no key, nothing is sent to the registrar."
  Forgery and impersonation: the key names the app and acts for no atSign;
  it is never logged, put in a URL or written to a file.

  # Was: "at_register with no registrar API key refuses before it reaches the
  # registrar", which exited non-zero saying to create an API key and set
  # AT_REGISTRAR_API_KEY, and sent nothing to the registrar.
  Scenario: at_register with no registrar API key sends the built-in key
    Given AT_REGISTRAR_API_KEY is not set
    When at_register runs with an email
    Then every request it sends to the registrar carries the built-in key as its Authorization header, and its output does not carry the key

  # Was: "at_activate onboard without a CRAM secret and with no registrar API
  # key refuses the same way", which exited non-zero with the same pointer and
  # sent nothing to the registrar.
  Scenario: at_activate onboard without a CRAM secret and with no registrar API key sends the built-in key
    Given AT_REGISTRAR_API_KEY is not set
    When at_activate onboard runs with an atSign and no -c
    Then the request it sends to the registrar carries the built-in key as its Authorization header, and no log line carries the key

  # Was: "at_activate onboard without a CRAM secret and with no registrar API
  # key refuses before it shows the backup prompt", which exited non-zero with
  # the same pointer before showing the backup prompt.
  Scenario: at_activate onboard without a CRAM secret and with a registrar API key a header cannot carry refuses before it shows the backup prompt
    Given AT_REGISTRAR_API_KEY holds a line break
    When at_activate onboard runs with an atSign, and neither -c nor -y
    Then it exits non-zero saying the key holds a character an HTTP header cannot carry, before showing the backup prompt, its output does not carry the key, and nothing is sent to the registrar

  Scenario: A registrar API key that is set is the one sent
    Given AT_REGISTRAR_API_KEY is set
    When at_register asks the registrar for a free atSign
    Then the request carries that key as its Authorization header, and no log line carries it

  # Added 2026-11-02 with Gary's choice above.
  Scenario: at_activate onboard with a registrar API key set sends that key, not the built-in one
    Given AT_REGISTRAR_API_KEY is set
    When at_activate onboard runs with an atSign and no -c
    Then the request it sends to the registrar carries that key as its Authorization header, not the built-in one, and no log line carries it

  Scenario: at_register with a registrar API key a header cannot carry refuses before it reaches the registrar, and never echoes the key
    Given AT_REGISTRAR_API_KEY holds a line break, or a character outside ASCII
    When at_register runs with an email
    Then it exits non-zero saying the key holds a character an HTTP header cannot carry, its output does not carry the key, and nothing is sent to the registrar

  Scenario: at_activate onboard with a CRAM secret needs no registrar API key
    Given AT_REGISTRAR_API_KEY is not set
    When at_activate onboard runs with an atSign and -c with its CRAM secret
    Then it activates as before, and sends nothing to the registrar
