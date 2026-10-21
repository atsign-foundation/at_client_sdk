# at_functional_test

Internal functional test suite for the at_client SDK. Not published.
See `test/` for the test cases.

`./runLocal.sh [BASE_PORT] [TEST_PATHS...]` runs it against a fresh
virtualenv. `test/upgrade_test.dart` checks that a store written by a released
at_client still works on this tree; see `../upgrade/README.md`.
