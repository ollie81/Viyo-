#!/usr/bin/env bash
# Vercel build: the Flutter app at /app/, the public website at /.
set -euo pipefail
git clone https://github.com/flutter/flutter.git -b stable --depth 1 _flutter_sdk
./_flutter_sdk/bin/flutter config --enable-web
./_flutter_sdk/bin/flutter pub get
./_flutter_sdk/bin/flutter build web --release --base-href /app/
rm -rf public
mkdir -p public
cp -R site/. public/
cp -R build/web public/app
