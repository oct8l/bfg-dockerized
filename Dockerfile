FROM amazoncorretto:25.0.0-alpine

## Sourced from https://rtyley.github.io/bfg-repo-cleaner/
ENV BFG_VERSION="1.14.0"
ENV BFG_CHECKSUM="1a75e9390541f4b55d9c01256b361b815c1e0a263e2fb3d072b55c2911ead0b7"
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
