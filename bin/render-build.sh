#!/usr/bin/env bash
# Runs on every deploy: installs everything, builds the web app into public/
# (Rails serves it from there), and updates both databases.
set -o errexit

bundle install

npm --prefix frontend ci --include=dev
npm --prefix frontend run build -- --outDir ../public

bin/rails db:migrate
bin/rails clickhouse:migrate
