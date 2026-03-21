FROM restic/restic:latest

RUN apk add --no-cache dcron

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

# Weekly backup: Sunday at 1:00 AM
RUN echo "0 1 * * 0 /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" \
    > /etc/crontabs/root

CMD ["crond", "-f", "-l", "2"]
