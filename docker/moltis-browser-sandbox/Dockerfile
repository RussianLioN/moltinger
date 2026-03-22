FROM browserless/chrome

ENV PREBOOT_CHROME=false

USER root
COPY docker/moltis-browser-sandbox/start-browserless-no-preboot.sh /usr/local/bin/start-browserless-no-preboot.sh
RUN chmod 0755 /usr/local/bin/start-browserless-no-preboot.sh
USER blessuser

ENTRYPOINT ["/usr/local/bin/start-browserless-no-preboot.sh"]
