FROM ghcr.io/cirruslabs/flutter:stable AS admin_build

WORKDIR /app

COPY apps/client/pubspec.yaml apps/client/pubspec.lock ./
RUN flutter config --enable-web && flutter pub get

COPY apps/client/ ./

ARG API_BASE_URL=https://lm.zalmanim.com/
RUN flutter build web --release --dart-define="API_BASE_URL=${API_BASE_URL}"

FROM ghcr.io/cirruslabs/flutter:stable AS artist_build

WORKDIR /app

COPY apps/artist_portal/pubspec.yaml apps/artist_portal/pubspec.lock ./
RUN flutter config --enable-web && flutter pub get

COPY apps/artist_portal/ ./

ARG ARTIST_API_BASE_URL=https://artists.zalmanim.com/
ARG ARTIST_LABEL_NAME=Zalmanim\ Artists
ARG ARTIST_PRIMARY_COLOR=B66A2C
ARG DEMO_SUBMISSION_TOKEN=TOKEN
RUN flutter build web --release \
    --dart-define="API_BASE_URL=${ARTIST_API_BASE_URL}" \
    --dart-define="LABEL_NAME=${ARTIST_LABEL_NAME}" \
    --dart-define="PRIMARY_COLOR=${ARTIST_PRIMARY_COLOR}" \
    --dart-define="DEMO_SUBMISSION_TOKEN=${DEMO_SUBMISSION_TOKEN}"

FROM nginx:1.27-alpine

COPY deploy/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=admin_build /app/build/web/ /usr/share/nginx/html/
COPY --from=artist_build /app/build/web/ /usr/share/nginx/artist/
COPY deploy/web/.well-known/security.txt /usr/share/nginx/html/.well-known/security.txt
COPY deploy/web/.well-known/security.txt /usr/share/nginx/artist/.well-known/security.txt
