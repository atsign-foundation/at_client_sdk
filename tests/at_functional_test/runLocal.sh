#!/bin/bash

echo "***********************************"
echo "*** Getting dependencies" && dart pub upgrade

echo "***"
echo "*** Running docker compose up" && docker compose -f test/docker-compose.yaml up -d

echo "***"
echo "*** Checking docker readiness" && dart run test/check_docker_readiness.dart

echo "***"
echo "*** Executing pkamLoad" && docker exec test-virtualenv-1 supervisorctl start pkamLoad

echo "***"
echo "*** Checking test environment" && dart run test/check_test_env.dart

echo "***"
echo "*** Clearing client test storage" && rm -rf test/hive

echo "***"
echo "*** Running tests" && dart test --concurrency=1 -r expanded

echo "***"
echo "***"
echo "Running docker compose down" && docker compose -f test/docker-compose.yaml down
echo "***********************************"
