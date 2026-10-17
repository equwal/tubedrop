# git clone https://github.com/equwal/dropin deps/dropin && docker build -t tubedrop .
FROM debian:trixie-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends sbcl curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSLo /tmp/quicklisp.lisp https://beta.quicklisp.org/quicklisp.lisp \
 && sbcl --non-interactive --load /tmp/quicklisp.lisp --eval '(quicklisp-quickstart:install)' \
 && echo '(load "/root/quicklisp/setup.lisp")' > /root/.sbclrc
WORKDIR /src
COPY . .
RUN cd deps/dropin && sbcl --non-interactive --load tests/self-check.lisp
RUN sbcl --non-interactive --load tests/self-check.lisp
RUN sbcl --non-interactive --load build.lisp

FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/tubedrop /usr/local/bin/tubedrop
ENV DROPIN_ROOT=/data TUBEDROP_CONFIG=/config TUBEDROP_PORT=8080
VOLUME ["/data", "/config"]
EXPOSE 8080
ENTRYPOINT ["tubedrop"]
CMD ["web"]
