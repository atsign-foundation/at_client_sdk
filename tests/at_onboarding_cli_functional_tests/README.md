
Please read these instructions before adding new/modifying onboarding functional tests

* If a secondary server is started with demo atsigns and pkam/encryption keys loaded,onboard will
  return an exception since the server is already in activated state.
* In order to test onboard, we need a server with only cram key available
* Hence pkamLoad script for onboarding functional tests is commented in .github/workflows/at_libraries.yaml
* To test authenticate method in AtOnboardingService, we need the pkam/encryption keys updated in server.
  This step is performed within the test before testing authenticate method. 
  Check _createKeys() method in at_onboarding_cli_test.dart. 
  You can use demo keys/generate keys file using demo data to test authenticate method.
* To test onboard method in AtOnboardingService, new key pairs will be generated during onboard flow.
  Hence demo keys cannot be used to test onboard method. 
  Use distinct atsign per test method to test onboarding since repeated run of onboard for same atsign 
  will fail with atsign already activated exception. 
  Delete the .atKeys file generated during onboard at the end of the test. 
  e.g enrollment_test.dart
* If you are running onboarding_cli functional tests in local setup,use virtual environment without pkamLoad 

