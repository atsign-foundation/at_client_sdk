# Should I Use at_common_flutter in My New Flutter App?

## Short Answer

Generally, no. `at_common_flutter` is an older package from the Atsign ecosystem and is largely considered legacy/deprecated in favor of more current packages. For new Flutter applications built on the atPlatform, you should evaluate whether you actually need it and consider the alternatives.

## What is at_common_flutter?

`at_common_flutter` was a Flutter package provided by Atsign that contained common UI widgets, utilities, and helpers shared across several Atsign Flutter applications. It was used internally across apps like the @wavi and @buzz reference applications.

## Why You Probably Should Not Use It

1. **Deprecated/Legacy Status**: The package has not been actively maintained in step with the broader atPlatform SDK evolution. Atsign has shifted its approach to providing more modular, purpose-built packages rather than a monolithic common library.

2. **Limited Documentation and Support**: Because it is considered legacy, you are unlikely to find up-to-date documentation or active community support for issues you encounter.

3. **Dependency Conflicts**: Older packages like this can introduce dependency version conflicts with current Flutter and Dart SDK versions, making it harder to keep your project up to date.

4. **Better Alternatives Exist**: The current atPlatform Flutter ecosystem offers more focused packages that are actively maintained.

## What to Use Instead

For new Flutter apps on the atPlatform, the recommended approach is:

- **`at_onboarding_flutter`**: For handling atSign onboarding (QR code scanning, pairing, authentication flows). This is the primary UI package you will need for most apps.
- **`at_client_mobile`**: The mobile-specific client SDK that wraps `at_client` with Flutter lifecycle management and secure storage.
- **`at_utils`** and **`at_commons`**: Low-level Dart utilities and common types, if needed directly.
- **`at_contacts_flutter`** or other domain-specific packages: If your app needs specific features like contacts, look for dedicated packages for those features.

## Recommendation

Start with the official Atsign documentation and pub.dev listings for the packages that match your app's specific needs. The core packages to begin with for a new atPlatform Flutter app are:

1. `at_client_mobile`
2. `at_onboarding_flutter`

Avoid pulling in `at_common_flutter` unless you have a specific, documented reason and have verified it is compatible with your current Flutter/Dart SDK version. If you saw it referenced in sample code or older tutorials, that content is likely outdated.

## How to Verify Current Status

Check the package's pub.dev page at `https://pub.dev/packages/at_common_flutter` and look at:
- The last publish date
- Whether it has a "discontinued" or "unlisted" badge
- The number of open issues on its GitHub repository
- Whether the Atsign team's current documentation references it

If the package has not been updated in a long time and is not referenced in current Atsign developer guides, treat it as deprecated and avoid using it in new projects.
