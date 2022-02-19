#!/bin/bash

echo "Getting dependencies" && dart pub get
echo "Starting docker-compose" && sudo docker-compose -f test/docker-compose.yaml up -d
echo "Checking docker readiness" && dart run test/check_docker_readiness.dart
echo "Executing pkamLoad" && sudo docker exec test_virtualenv_1 supervisorctl start pkamLoad
echo "Checking test environment" && dart run test/check_test_env.dart
echo "Running tests" && dart test --concurrency=1
