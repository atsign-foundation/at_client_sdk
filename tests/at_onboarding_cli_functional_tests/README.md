
Please read these instructions before adding new/modifying onboarding functional tests

* **Never let a test write to `~/.atsign/keys`.** That directory holds a developer's
  live personal keyfiles, and it is what `at_onboarding_cli` falls back to whenever
  `AtOnboardingPreference.atKeysFilePath` is left null or `auth_cli` is invoked
  without `-k`. Get every keyfile path from `testKeysFile()` in
  `test/utils/test_keys_dir.dart`; it returns a path under `test/.tmp_keys/`, which
  is emptied when a run starts, so an aborted run cannot fail the next one with
  "Keys file already exists".

* If a secondary server is started with demo atsigns and pkam/encryption keys loaded,onboard will
  return an exception since the server is already in activated state.
* In order to test onboard, we need a server with only cram key available
* Hence pkamLoad script for onboarding functional tests is commented in .github/workflows/at_libraries.yaml
* To test authenticate method in AtOnboardingService, we need the pkam/encryption keys updated in server.
  This step is performed within the test before testing authenticate method. 
  Check _createKeys() method in at_onboarding_cli_test.dart. 
  You can use demo keys/generate keys file using demo data to test authenticate method.
* To test activation (the CLI's `activate` command, over `Atsign.activate`), new key pairs will be
  generated during the activation flow. Hence demo keys cannot be used to test activation.
  Use a distinct atsign per test method to test activation since a repeated run of activation for the
  same atsign will fail with an atsign already activated exception.
  Delete the .atKeys file generated during activation at the end of the test.
  e.g enrollment_test.dart
* If you are running onboarding_cli functional tests in local setup,use virtual environment without pkamLoad 

