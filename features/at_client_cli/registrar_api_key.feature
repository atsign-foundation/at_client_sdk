Feature: at_register and at_activate take the registrar API key from the environment

  The registrar API key names the app to the registrar. at_client_cli
  carries none: an app developer creates one via the registrar at
  my.atsign.com and sets AT_REGISTRAR_API_KEY.

  Races, replay: none arise.
  DoS: with no key, nothing is sent to the registrar.
  Forgery and impersonation: the key names the app and acts for no atSign;
  it is never logged, put in a URL or written to a file.

  Scenario: at_register with no registrar API key refuses before it reaches the registrar
    Given AT_REGISTRAR_API_KEY is not set
    When at_register runs with an email
    Then it exits non-zero saying to create an API key via the registrar at my.atsign.com and set AT_REGISTRAR_API_KEY, and nothing is sent to the registrar

  Scenario: at_activate onboard without a CRAM secret and with no registrar API key refuses the same way
    Given AT_REGISTRAR_API_KEY is not set
    When at_activate onboard runs with an atSign and no -c
    Then it exits non-zero with the same pointer, and nothing is sent to the registrar

  Scenario: A registrar API key that is set is the one sent
    Given AT_REGISTRAR_API_KEY is set
    When at_register asks the registrar for a free atSign
    Then the request carries that key as its Authorization header, and no log line carries it

  Scenario: at_register with a registrar API key a header cannot carry refuses before it reaches the registrar, and never echoes the key
    Given AT_REGISTRAR_API_KEY holds a line break, or a character outside ASCII
    When at_register runs with an email
    Then it exits non-zero saying the key holds a character an HTTP header cannot carry, its output does not carry the key, and nothing is sent to the registrar

  Scenario: at_activate onboard with a CRAM secret needs no registrar API key
    Given AT_REGISTRAR_API_KEY is not set
    When at_activate onboard runs with an atSign and -c with its CRAM secret
    Then it activates as before, and sends nothing to the registrar
