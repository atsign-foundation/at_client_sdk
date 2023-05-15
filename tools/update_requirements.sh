#!/bin/bash
# When Dependabot updates poetry.lock and pyproject.toml it fails to
# update the requirements.txt, which is what we actually use to pull
# in our Python dependencies. So we need to run this to generate a
# new requirements.txt from the updated files.
poetry export --format requirements.txt --output requirements.txt
# of course this assumes that poetry is installed, which is done by:
## curl -sSL https://install.python-poetry.org | python3 -
# see https://github.com/atsign-foundation/at_server/pull/1065 for
# how this stuff got here in the first place
