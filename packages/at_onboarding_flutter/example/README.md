<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

## at_onboarding_flutter example
The at_onboarding_flutter package is designed to make it easy to add onboarding flow to a flutter app on atPlatform with the following features:
- Supports Generate free atSign.
- Supports multiple atSign onboarding.
- Flexibility of either pairing an atSign with a QRCode or an Atkey file.
- Dark mode
- Reset/Sign out button.

### Give it a try
This package includes a working sample application in the [example](https://github.com/atsign-foundation/at_widgets/tree/trunk/at_onboarding_flutter/example) directory that demonstrates the key features of the package. To create a personalized copy, use ```at_app create``` as shown below or check it out on GitHub.

```sh
$ flutter pub global activate at_app 
$ at_app create --sample=<package ID> <app name> 
$ cd <app name>
$ flutter run
```
Notes: 
1. You only need to run ```flutter pub global activate``` once
2. Use ```at_app.bat``` for Windows


## How it works

at_onboarding_flutter widget handles secure management of secret keys for an atSign as cryptographically secure replacement for usernames and passwords.

The package provides the UI widgets required for the onboarding flow collectively in a single call, `Onboarding()`.

You can customize them by using the different parameters in it. Also, the package uses the theme from the parent app.

The package also manages all the data it needs for you.

Like everything else we do, this package and even the sample application are open source software which means we love it when you gift us with your feedback, contributions and even any bugs that you help us to discover. See [CONTRIBUTING.md](https://github.com/atsign-foundation/at_widgets/blob/trunk/CONTRIBUTING.md) for detailed guidance on how to setup tools, tests and make a pull request.