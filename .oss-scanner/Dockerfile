# Anthropic OSS Scanner: build dependencies while online; audit offline.
FROM rocker/r-ver:4.4.3
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev libssl-dev libxml2-dev libgit2-dev \
    libfontconfig1-dev libfreetype6-dev libpng-dev libtiff-dev libjpeg-dev \
    libharfbuzz-dev libfribidi-dev libicu-dev libglpk-dev \
    pandoc git make g++ && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . /src
RUN Rscript -e 'install.packages(c("remotes","testthat"), repos="https://cloud.r-project.org"); remotes::install_deps(".", dependencies=TRUE, upgrade="never", repos="https://cloud.r-project.org")'
RUN R CMD INSTALL . 
# Smoke test during build, before the scanner disables networking.
RUN Rscript -e 'stopifnot(requireNamespace("dataganger", quietly=TRUE)); packageVersion("dataganger")'
CMD ["bash"]
