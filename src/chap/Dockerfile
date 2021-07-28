# Build deps
FROM elixir:alpine as builder

ENV TERM=xterm
ENV PHX_VERSION 1.5.9

ARG build_env=prod
ENV MIX_ENV=${build_env}

RUN apk update && apk upgrade && \
    apk add --no-cache bash git openssh

RUN set -x &&\
	mix local.hex --force &&\
	mix local.rebar --force &&\
	mix archive.install hex phx_new $PHX_VERSION --force

COPY mix.exs /opt/app/chap/mix.exs
WORKDIR /opt/app/chap
RUN mix do deps.get, compile

COPY . /opt/app/chap
RUN mix release chap

ENV REPLACE_OS_VARS=true
ENV SHELL=/bin/bash

EXPOSE 4000

CMD ./_build/prod/rel/chap/bin/chap start
