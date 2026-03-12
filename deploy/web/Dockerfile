FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

COPY apps/client/pubspec.yaml apps/client/pubspec.lock ./
RUN flutter config --enable-web && flutter pub get

COPY apps/client/ ./

ARG API_BASE_URL=https://lmapi.zalmanim.com/
RUN flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

FROM nginx:1.27-alpine

COPY deploy/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web/ /usr/share/nginx/html/
