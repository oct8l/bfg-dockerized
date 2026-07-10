FROM amazoncorretto:25.0.3-alpine@sha256:32d81edae73e1670244827c2f12e5bcf0d335f035b538455fe9d02eb0771d41b

## Sourced from https://rtyley.github.io/bfg-repo-cleaner/
ENV BFG_VERSION="1.15.0"
ENV BFG_CHECKSUM="dfe2885adc2916379093f02a80181200536856c9a987bf21c492e452adefef7a"
ENV HOME="/home/bfg"

RUN apk --no-cache upgrade && \
    apk add --no-cache shadow && \
    adduser -D -h $HOME bfg && \
    chown -R bfg:bfg $HOME && \
    wget "https://repo1.maven.org/maven2/com/madgag/bfg/$BFG_VERSION/bfg-$BFG_VERSION.jar" \
    -O "bfg-$BFG_VERSION.jar" \
    && echo "$BFG_CHECKSUM  bfg-$BFG_VERSION.jar" | sha256sum -c - \
    && mv "bfg-$BFG_VERSION.jar" /home/bfg/bfg.jar

WORKDIR "$HOME/workspace"

USER bfg

ENTRYPOINT ["java", "-jar", "/home/bfg/bfg.jar"]
