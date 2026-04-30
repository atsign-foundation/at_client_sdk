#!/bin/bash

echo "***********************************"
echo "*** Getting dependencies" && dart pub get

cd test

echo "***"
echo "*** Running docker compose down" && docker compose down
echo "*** Running docker compose pull" && docker compose pull
echo "*** Running docker compose up" && docker compose up -d

cd ..

echo "***"
echo "*** Checking docker readiness" && dart run test/check_docker_readiness.dart

echo "***"
echo "*** Executing pkamLoad" && docker exec test-virtualenv-1 supervisorctl start pkamLoad

echo "***"
echo "*** Checking test environment" && dart run test/check_test_env.dart

echo "***"
echo "*** Clearing client test storage" && rm -rf test/hive && rm -f test/testData/*.atKeys

echo "***"
echo "*** Running tests" && dart test --concurrency=1 -r expanded

echo "***"
echo "***"
echo "*** Running docker compose down" && docker compose -f test/docker-compose.yaml down
echo "***********************************"
