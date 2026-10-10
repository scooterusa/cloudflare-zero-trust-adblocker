FROM ruby:3.3-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN git clone --depth 1 \
    https://github.com/scooterusa/cloudflare-zero-trust-adblocker.git /app

RUN bundle config set without 'development:test' \
    && bundle install

CMD ["bundle", "exec", "ruby", "lib/main.rb"]
