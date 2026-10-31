FROM dart:3.9 AS buildimage
ENV HOMEDIR=/atsign
ENV BINARYDIR=${HOMEDIR}/at_activate
ENV USER_ID=1024
ENV GROUP_ID=1024
WORKDIR ${HOMEDIR}
# Context for this Dockerfile needs to be the root of {at_client_sdk_repo}:
# at_client_cli resolves its at_* dependencies from the pub workspace there.
# If building manually then (from the repo root):
## docker build -f packages/at_client_cli/Dockerfile -t atsigncompany/at_activate .
# The workspace root also holds the Flutter packages, which this image cannot
# resolve, so the at_* packages at_client_cli needs are copied in, taken out of
# the workspace, and wired together with path overrides.
COPY packages/at_auth packages/at_auth
COPY packages/at_chops packages/at_chops
COPY packages/at_client packages/at_client
COPY packages/at_client_cli packages/at_client_cli
COPY packages/at_commons packages/at_commons
COPY packages/at_lookup packages/at_lookup
COPY packages/at_utils packages/at_utils
WORKDIR ${HOMEDIR}/packages/at_client_cli
RUN \
  set -e ; \
  mkdir -p "$BINARYDIR" ; \
  case "$(dpkg --print-architecture)" in \
        amd64) \
            ARCH="x64";; \
        armhf) \
            ARCH="arm";; \
        arm64) \
            ARCH="arm64";; \
    esac; \
  sed -i '/^resolution: workspace$/d' ../*/pubspec.yaml ; \
  printf 'dependency_overrides:\n' > pubspec_overrides.yaml ; \
  for p in at_auth at_chops at_client at_commons at_lookup at_utils; do \
    printf '  %s:\n    path: ../%s\n' "$p" "$p" >> pubspec_overrides.yaml ; \
  done ; \
  dart pub get ; \
  dart compile exe bin/at_activate.dart -o "$BINARYDIR"/at_activate ; \
  tar cvzf /atsign/at_activate-linux-"$ARCH".tgz "$BINARYDIR"/at_activate


# Second stage of build FROM scratch
FROM scratch AS export-stage
COPY --from=buildimage /atsign/at_activate-linux-*.tgz .
