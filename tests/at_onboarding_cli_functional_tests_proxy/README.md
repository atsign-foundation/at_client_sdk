# at_onboarding_cli_functional_tests_proxy

## Prerequisites

- Docker Compose
- Docker Engine
- this line in `/etc/hosts`: `127.0.0.1       vip.ve.atsign.zone`

## Running the Tests

1. Start the docker containers

```bash
sudo docker-compose up -d
```

2. Run an individual test

```bash
dart test tests/<test name>.dart
```
