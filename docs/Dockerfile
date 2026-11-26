ARG QUARTO_PLATFORM=linux/amd64
FROM --platform=${QUARTO_PLATFORM} ghcr.io/quarto-dev/quarto:1.10.20 AS build
WORKDIR /docs
COPY . .
RUN quarto render

FROM nginxinc/nginx-unprivileged:stable-alpine
COPY --from=build /docs/_site/ /usr/share/nginx/html/
