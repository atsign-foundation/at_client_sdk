Feature: A keyfile that is not a JSON object says why and where, and none of its text
  An app that cannot read an atKeys file tells its user why. FileAtKeysIo
  reports a keyfile that is not a JSON object with AtKeysFormatException, a
  FormatException, so a catch written for the FormatException earlier
  release candidates threw still catches it. It carries the JSON parser's
  reason and the 1-based character where the parser stopped, and nothing of
  the file's text. A passphrase-protected keyfile whose decrypted content
  does not parse is reported as a decryption failure, as before, since an
  incorrect passphrase usually leaves exactly that. at_client re-exports
  the exception, so an app built on either platform package names it.

  Races: none arise; a read parses one snapshot of the file.
  Replay: none arise; nothing is sent or checked.
  Denial of service: none arise; the report is a fixed message, a reason and
  a number, whatever the file's size.
  Forgery and impersonation: none arise; a keyfile that does not parse
  opens no client.
  Key material: the exception's source is null, its reason is the parser's
  fixed wording, and its position a number, so neither its fields nor its
  message hold the file's text.

  Scenario: A keyfile cut short names the parser's reason and the character
    Given an atKeys file whose text ends partway through a key
    When FileAtKeysIo reads it
    Then it throws AtKeysFormatException with the parser's reason and the 1-based character, holding none of the file's text

  Scenario: A keyfile that is valid JSON but not an object says so
    Given an atKeys file holding a JSON array
    When FileAtKeysIo reads it
    Then it throws AtKeysFormatException saying it is not a JSON object, with no character

  Scenario: A decrypted keyfile that does not parse is a decryption failure
    Given a passphrase-protected atKeys file whose decrypted content is cut short
    When FileAtKeysIo reads it with the right passphrase
    Then it throws AtDecryptionException naming the reason and the character, holding none of the decrypted text

  Scenario: An app built on at_client_flutter matches it by its fields
    Given an atKeys file whose text ends partway through a key
    When the app reads it through at_client_flutter's FileAtKeysIo
    Then it catches AtKeysFormatException by name and reads its reason and position
