# syntax=docker/dockerfile:1
# Build do client web — multi-stage: flutter build web (release) + nginx estático.
#
# ATENÇÃO: os dart-defines (API_URL/LIVEKIT_URL) são TEMPO DE COMPILAÇÃO —
# mudar URL exige rebuild (`docker compose build web`).
# Os valores padrão apontam para o lab local; produção/VPS passa outros via
# build args (ex.: https://app.4funcod.dev e wss://livekit.4funcod.dev).
#
# Estágio do SDK: baixa o tarball OFICIAL do Flutter pinado (FLUTTER_VERSION),
# em vez de imagem cirruslabs — as tags `stable`/`latest` do cirruslabs estavam
# com Dart 3.12.0 e o pubspec exige ^3.12.2 (Flutter 3.44.4 = Dart 3.12.2, igual
# ao SDK do host — validado 24/08/2026).

FROM ubuntu:24.04 AS flutter
ARG FLUTTER_VERSION=3.44.4
# Camadas separadas: apt e download ficam em cache independente do que vier depois.
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl unzip xz-utils git ca-certificates
RUN curl -fsSL -o /tmp/flutter.tar.xz \
        "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && tar xf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz
# O tar preserva dono/build-machine do SDK; o git do flutter tool recusa
# "dubious ownership" sem o safe.directory (validado 24/08/2026).
RUN git config --global --add safe.directory /opt/flutter \
    && /opt/flutter/bin/flutter config --no-analytics \
    && /opt/flutter/bin/flutter precache --web
ENV PATH="/opt/flutter/bin:${PATH}"

FROM flutter AS build
WORKDIR /app

ARG API_URL=https://192.168.0.217:8443
ARG LIVEKIT_URL=wss://192.168.0.217:7443

# Dependências primeiro (cache de camada do docker)
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release \
    --dart-define=API_URL=$API_URL \
    --dart-define=LIVEKIT_URL=$LIVEKIT_URL

FROM nginx:1.27-alpine AS runtime
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
