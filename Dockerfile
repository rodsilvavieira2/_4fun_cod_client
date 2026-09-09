# syntax=docker/dockerfile:1
# Web não é mais target suportado pelo 4FunCode.
#
# Este Dockerfile existia para publicar o client como site estático. Mantemos
# o arquivo para falhar com mensagem explícita caso algum pipeline antigo ainda
# tente construir a imagem.

FROM alpine:3.20
RUN echo "ERRO: build web do 4FunCode não é suportado. Use os targets desktop Linux/Windows." >&2 && exit 1
