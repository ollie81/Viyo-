#!/usr/bin/env bash
# Vercel build: the Flutter app at /app/, the public website at /.
set -euo pipefail
git clone https://github.com/flutter/flutter.git -b stable --depth 1 _flutter_sdk
./_flutter_sdk/bin/flutter config --enable-web
./_flutter_sdk/bin/flutter pub get
./_flutter_sdk/bin/flutter build web --release --base-href /app/
rm -rf public
mkdir -p public
# Regenerate the website pages from site_src/build_site.py, so a change there goes live without
# also committing the generated site/*.html. Falls back to the committed pages if it can't run.
python3 site_src/build_site.py || echo "Website generator unavailable; using the committed pages in site/."
cp -R site/. public/
cp -R build/web public/app
