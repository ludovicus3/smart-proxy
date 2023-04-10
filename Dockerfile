# Base container that is used for both building and running the app
FROM quay.io/centos/centos:stream8 as base
ARG RUBY_VERSION="2.7"

RUN \
  dnf upgrade -y && \
  dnf module enable ruby:${RUBY_VERSION} -y && \
  dnf install ruby{,gems} rubygem-{rake,bundler} -y && \
  dnf clean all

ARG HOME=/home/foreman-proxy
WORKDIR $HOME
RUN groupadd -r foreman-proxy -f -g 0 && \
    useradd -u 1001 -r -g foreman-proxy -d $HOME -s /sbin/nologin \
    -c "Foreman Proxy Application User" foreman-proxy && \
    chown -R 1001:0 $HOME && \
    chmod -R g=u ${HOME}

# Temp container that download gems/npms and compile assets etc
FROM base as builder

ENV BUNDLER_SKIPPED_GROUPS="test development"

RUN \
  dnf install -y redhat-rpm-config git \
    gcc-c++ make bzip2 gettext tar \
    libxml2-devel libcurl-devel ruby-devel \ 
    libvirt-devel systemd-devel krb5-devel && \
  dnf clean all

ARG HOME=/home/foreman-proxy
USER 1001
WORKDIR $HOME
COPY --chown=1001:0 . ${HOME}/

RUN bundle config set --local without "${BUNDLER_SKIPPED_GROUPS}" && \
  bundle config set --local clean true && \
  bundle config set --local path vendor && \
  bundle config set --local jobs 5 && \
  bundle config set --local retry 3
RUN bundle install && \
  bundle binstubs --all && \
  rm -rf vendor/ruby/*/cache/*.gem && \
  find vendor/ruby/*/gems -name "*.c" -delete && \
  find vendor/ruby/*/gems -name "*.o" -delete

USER 0
RUN chgrp -R 0 ${HOME} && \
    chmod -R g=u ${HOME}

USER 1001

FROM base

USER 0

RUN mkdir -p /etc/foreman-proxy/settings.d

ARG HOME=/home/foreman-proxy

USER 1001
WORKDIR ${HOME}
COPY --chown=1001:0 . ${HOME}/
COPY --from=builder --chown=1001:0 ${HOME}/.bundle/config ${HOME}/.bundle/config
COPY --from=builder --chown=1001:0 ${HOME}/Gemfile.lock ${HOME}/Gemfile.lock
COPY --from=builder --chown=1001:0 ${HOME}/vendor/ruby ${HOME}/vendor/ruby
RUN ln -s /etc/foreman-proxy/settings.yml ${HOME}/config/settings.yml


RUN date -u > BUILD_TIME

# Start the main process.
CMD ${HOME}/bin/smart-proxy

EXPOSE 8080/tcp
EXPOSE 8443/tcp
