FROM ruby:3.3-bookworm

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends chromium fonts-liberation tzdata ca-certificates dumb-init && \
    rm -rf /var/lib/apt/lists/*

ENV BROWSER_PATH=/usr/bin/chromium
WORKDIR /app

COPY Gemfile Gemfile.lock* ./
RUN bundle install

COPY umn_cookie_audit.rb ./

ENTRYPOINT ["dumb-init", "--"]
CMD ["ruby", "umn_cookie_audit.rb", "--sites", "/data/sites.txt", "--output", "/data/report.csv"]
