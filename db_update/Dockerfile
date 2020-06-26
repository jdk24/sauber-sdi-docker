FROM alpine:3.12.0

COPY pgdump.sh /.
RUN chmod 775 pgdump.sh
RUN apk add postgresql-client

CMD ["/usr/bin/sh","docker-entrypoint.sh"]