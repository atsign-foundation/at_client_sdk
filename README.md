<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![Build Status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml)
[![GitHub License](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/atsign-foundation/at_client_sdk/badge)](https://api.securityscorecards.dev/projects/github.com/atsign-foundation/at_client_sdk)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/8098/badge)](https://www.bestpractices.dev/projects/8098)

# at_client_sdk
This repo contains two versions of the at_client_sdk that you can choose from 
depending on what kind of device you are targeting for your application.

* [at_client](./packages/at_client) a non platform specific SDK that can be used for
writing things like command line applications and headless apps for Internet
of Things (IoT) devices.

* [at_client_mobile](./packages/at_client_mobile) an SDK specifically written for iOS and 
Android apps with support for secure storage and keys backup on the device with
embedded storage and hardware trusted root keychain.
