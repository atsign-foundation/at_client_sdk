FROM dart:2.19.4@sha256:5d2f42239d719bef7fe60abb37273aea16d8526980662b696c218663ac005d96 AS buildimage
ENV HOMEDIR=/atsign
ENV BINARYDIR=${HOMEDIR}/at_activate
ENV USER_ID=1024
ENV GROUP_ID=1024
WORKDIR ${HOMEDIR}
# Context for this Dockerfile needs to be {at_libraries_repo}/packages/at_onboarding_cli
# If building manually then (from packages/at_onboarding_cli):
## docker build -t atsigncompany/at_activate .
COPY . .
RUN \
  mkdir -p "$HOMEDIR" ; \
  mkdir -p "$BINARYDIR" ; \
  case "$(dpkg --print-architecture)" in \
        amd64) \
            ARCH="x64";; \
        armhf) \
            ARCH="arm";; \
        arm64) \
            ARCH="arm64";; \
    esac; \
  dart pub get ; \
  dart pub upgrade ; \
  dart compile exe bin/activate_cli.dart -o "$BINARYDIR"/at_activate ; \
  tar cvzf /atsign/at_activate-linux-"$ARCH".tgz "$BINARYDIR"/at_activate

  
# Second stage of build FROM scratch
FROM scratch AS export-stage
COPY --from=buildimage /atsign/at_activate-linux-*.tgz .