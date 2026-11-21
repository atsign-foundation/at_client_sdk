Feature: at_activate enroll resumes the request its keyfile already holds

  at_activate enroll run on a keyfile already waiting on an enrollment
  request resumes that request rather than submitting another, whatever app
  or device name it was filed under: the request for the app and device it
  is given first, else that app's on any device, else the keyfile's one
  request. When the request it resumes was filed under another app or device
  name, it says the names the keyfile records for it. It shows the id and
  each name with its control characters escaped, clipped at 180 characters.
  A request the manager denies, or that expires, is cleared from the keyfile
  by the next run, which reports it.

  Races: a request another process on this device completes or abandons
  first is found as it then is: a completed one leaves live keys, which
  enroll refuses, and an abandoned one leaves nothing to resume, so a new
  request is submitted.
  Replay: none arises; resuming sends no new request, and the wait polls the
  request it resumed as before.
  DoS: none arises; resuming adds no poll, and a request nobody decides
  keeps a run waiting only until the manager denies it or it expires.
  Forgery and impersonation: enroll adopts only a request in the keyfile it
  is given, which only programs on this device write, and says the names it
  was filed under, which are the names the manager approves.

  Scenario Outline: enroll adopts the request its keyfile holds under another app or device name
    Given a keyfile holding a pending enrollment <id> for @alice, filed by app "buzz" on device "phone"
    When at_activate enroll runs for @alice with app "<app>" on device "<device>" on that keyfile
    Then it sends nothing new, says "Resuming enrollment <id>, filed as buzz on phone", and waits on that request

    Examples:
      | app  | device |
      | wavi | phone  |
      | buzz | tablet |

  Scenario: enroll resumes this app's request from another device before another app's
    Given a keyfile holding pending enrollments for @alice filed by app "wavi" on device "old-phone" and by app "buzz" on device "phone"
    When at_activate enroll runs for @alice with app "wavi" on device "new-phone" on that keyfile
    Then it sends nothing new, says "Resuming enrollment <id>, filed as wavi on old-phone", and waits on that request

  Scenario: enroll shows a recorded app or device name with its control characters escaped
    Given a keyfile holding a pending enrollment <id> for @alice, filed by app "wa<ESC>vi" on device "pho<CR>ne"
    When at_activate enroll runs for @alice with app "buzz" on device "tablet" on that keyfile
    Then it says "Resuming enrollment <id>, filed as wa\u001bvi on pho\u000dne", and nothing it prints, apart from its own colour and line-redraw codes, holds an ESC or a carriage return
