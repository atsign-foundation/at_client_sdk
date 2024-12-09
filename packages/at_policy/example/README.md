# at_policy examples

## Overview
- Imagine a client which is making a request to some service; it can make 
  three types of request
  - `getPublicInfo`
  - `getProtectedInfo`
  - `getConfidentialInfo`
- The service needs to make a policy decision for each request - should it 
  respond with the info, or respond with a "not permitted" error? It 
  asks `policy` for information about how it should respond

## Programmes
- `client.dart`
  - sends requests to `service`
- `service.dart`
    - listens for requests from `client` and determines client intent
    - sends message to `policy` requesting info about what policy decision it 
      should make regarding the client's intent
- `policy.dart`
  - listens for requests from `service` with policy intents
  - responds with the info that `service` requires in order to be able to 
    make a policy decision
