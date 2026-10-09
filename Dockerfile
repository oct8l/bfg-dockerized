FROM amazoncorretto:27-alpine@sha256:6fba5f9f2f4730e2d3e81055ce0378a8587c12a48611ee545c5db04c3a28f889

## Sourced from https://rtyley.github.io/bfg-repo-cleaner/
# renovate: datasource=github-releases depName=rtyley/bfg-repo-cleaner extractVersion=^v(?<version>.+)$ versioning=semver
ENV BFG_VERSION="1.15.0"
# renovate: datasource=repology depName=alpine_3_24/shadow versioning=apk
ENV SHADOW_VERSION="4.18.0-r1"
ENV HOME="/home/bfg"

RUN apk --no-cache upgrade && \
    apk add --no-cache "shadow=$SHADOW_VERSION" && \
    adduser -D -h $HOME bfg && \
    chown -R bfg:bfg $HOME && \
    wget -q "https://repo1.maven.org/maven2/com/madgag/bfg/$BFG_VERSION/bfg-$BFG_VERSION.jar" \
        -O "bfg-$BFG_VERSION.jar" \
    && wget -q "https://repo1.maven.org/maven2/com/madgag/bfg/$BFG_VERSION/bfg-$BFG_VERSION.jar.sha1" \
        -O bfg.sha1.expected \
    && printf '%s  %s\n' "$(cat bfg.sha1.expected)" "bfg-$BFG_VERSION.jar" > bfg.sha1 \
    && sha1sum -c bfg.sha1 \
    && rm bfg.sha1 bfg.sha1.expected \
    && mv "bfg-$BFG_VERSION.jar" /home/bfg/bfg.jar

WORKDIR "$HOME/workspace"

USER bfg

ENTRYPOINT ["java", "-jar", "/home/bfg/bfg.jar"]
