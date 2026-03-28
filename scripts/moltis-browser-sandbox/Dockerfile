ARG BASE_IMAGE=browserless/chrome
FROM ${BASE_IMAGE}

USER root

COPY entrypoint.sh /usr/local/bin/moltis-browser-sandbox-entrypoint.sh

RUN chmod 0755 /usr/local/bin/moltis-browser-sandbox-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/moltis-browser-sandbox-entrypoint.sh"]
