### Build our own image since Corretto doesn't get a multiarch build
##
#### Copied from https://github.com/corretto/corretto-docker/blob/main/17/jdk/alpine/3.19/Dockerfile
###----------------------
##FROM alpine:3.19
##
##ARG version=17.0.11.9.1
##
### Please note that the THIRD-PARTY-LICENSE could be out of date if the base image has been updated recently.
### The Corretto team will update this file but you may see a few days' delay.
##RUN wget -O /THIRD-PARTY-LICENSES-20200824.tar.gz https://corretto.aws/downloads/resources/licenses/alpine/THIRD-PARTY-LICENSES-20200824.tar.gz && \
##    echo "82f3e50e71b2aee21321b2b33de372feed5befad6ef2196ddec92311bc09becb  /THIRD-PARTY-LICENSES-20200824.tar.gz" | sha256sum -c - && \
##    tar x -ovzf THIRD-PARTY-LICENSES-20200824.tar.gz && \
##    rm -rf THIRD-PARTY-LICENSES-20200824.tar.gz && \
##    wget -O /etc/apk/keys/amazoncorretto.rsa.pub https://apk.corretto.aws/amazoncorretto.rsa.pub && \
##    SHA_SUM="6cfdf08be09f32ca298e2d5bd4a359ee2b275765c09b56d514624bf831eafb91" && \
##    echo "${SHA_SUM}  /etc/apk/keys/amazoncorretto.rsa.pub" | sha256sum -c - && \
##    echo "https://apk.corretto.aws" >> /etc/apk/repositories && \
##    apk add --no-cache amazon-corretto-17=$version-r0 && \
##    rm -rf /usr/lib/jvm/java-17-amazon-corretto/lib/src.zip
##
##
##ENV LANG C.UTF-8
##
##ENV JAVA_HOME=/usr/lib/jvm/default-jvm
##ENV PATH=$PATH:/usr/lib/jvm/default-jvm/bin
###----------------------
FROM amazoncorretto:22-alpine

# Now BFG stuff
## Sourced from https://rtyley.github.io/bfg-repo-cleaner/
ENV BFG_VERSION="1.14.0"
ENV BFG_CHECKSUM="1a75e9390541f4b55d9c01256b361b815c1e0a263e2fb3d072b55c2911ead0b7"
ENV HOME /home/bfg

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
