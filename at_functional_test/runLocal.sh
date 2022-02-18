#!/bin/bash

echo "Getting dependencies" && dart pub get

cd test || exit

echo "Starting docker-compose" && docker-compose up -d

cd ..
echo "Checking docker readiness" && dart run test/check_docker_readiness.dart

echo "Executing pkamLoad" && docker exec test_virtualenv_1 supervisorctl start pkamLoad

echo "Checking test environment" && dart run test/check_test_env.dart

echo "Running tests" && dart test --concurrency=1
