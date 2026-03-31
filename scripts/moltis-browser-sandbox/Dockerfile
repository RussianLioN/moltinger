ARG BASE_IMAGE=browserless/chrome
FROM ${BASE_IMAGE}

ARG SANDBOX_SPEC_SHA=unknown

USER root

LABEL io.moltinger.browser-sandbox.spec-sha="${SANDBOX_SPEC_SHA}"

COPY entrypoint.sh /usr/local/bin/moltis-browser-sandbox-entrypoint.sh

RUN chmod 0755 /usr/local/bin/moltis-browser-sandbox-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/moltis-browser-sandbox-entrypoint.sh"]
