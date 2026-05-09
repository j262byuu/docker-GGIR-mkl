# =============================================================================
# GGIR Docker Image
# Base: rocker/r-ver (Ubuntu-based, minimal, version-locked)
# Target: batch processing on HPC (Singularity/Apptainer compatible)
# GGIR source: GitHub master (wadpac/GGIR), always latest version
# Parallel: foreach + doParallel (fork-based, no extra system deps needed)
# BLAS/LAPACK: Intel MKL (Math Kernel Library) for hardware acceleration
# =============================================================================
FROM rocker/r-ver:4.5.3
LABEL maintainer="j262byuu@gmail.com" \
      description="GGIR for batch accelerometer data processing with Intel MKL"
# -----------------------------------------------------------------------------
# Locale & timezone: UTF-8 + UTC to avoid edge cases in GGIR's timestamp parsing
# -----------------------------------------------------------------------------
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8
ENV TZ=Etc/UTC
# -----------------------------------------------------------------------------
# MKL & Threading Environment Variables (CRITICAL FOR GGIR)
#
# GGIR parallelizes via doParallel (forked R workers). Each worker must use a
# single-threaded BLAS — otherwise N workers × M MKL threads oversubscribes the
# CPU, and the fork-OpenBLAS-style per-thread buffer bloat eats RAM linearly
# in N. The whole point of using MKL here is per-process memory footprint.
#
# MKL_THREADING_LAYER=SEQUENTIAL: do not load any threading runtime inside MKL.
#   Stronger than NUM_THREADS=1 alone — no libgomp pulled into the process,
#   no OpenMP state across fork(), minimum per-worker RSS.
#
# MKL_NUM_THREADS / OMP_NUM_THREADS=1: belt-and-suspenders in case any
#   transitive component outside MKL itself consults these.
# -----------------------------------------------------------------------------
ENV MKL_THREADING_LAYER=SEQUENTIAL
ENV MKL_NUM_THREADS=1
ENV OMP_NUM_THREADS=1
# -----------------------------------------------------------------------------
# System dependencies
# Rationale for each:
#   libssl-dev           : read.gt3x, GGIRread, remotes (HTTPS downloads)
#   libcurl4-openssl-dev : remotes (GitHub install)
#   libxml2-dev          : unisensR (XML parsing for Movisens format)
#   zlib1g-dev           : data.table (compression)
#   git                  : remotes::install_github
#   intel-mkl            : Intel Math Kernel Library for BLAS/LAPACK acceleration
# -----------------------------------------------------------------------------
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      libssl-dev \
      libcurl4-openssl-dev \
      libxml2-dev \
      zlib1g-dev \
      git \
      intel-mkl \
 && update-alternatives --set libblas.so.3-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/libmkl_rt.so \
 && update-alternatives --set liblapack.so.3-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/libmkl_rt.so \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
      /usr/share/doc/intel-mkl* \
      /usr/share/man/man*
# -----------------------------------------------------------------------------
# R packages
# - Rcpp     : required for GGIR's Rcpp-accelerated ENMO path (j262byuu/GGIR
#              fork) and as a build dependency for packages with compiled code
# - remotes  : needed to install from GitHub
# - unisensR : enables GGIR's Movisens (.unisens) reader; pairs with libxml2-dev
# - GGIR     : installed from official upstream (wadpac/GGIR)
#              To use the Rcpp-optimized fork instead:
#              remotes::install_github("j262byuu/GGIR@feature/rcpp-enmo", ...)
# - dependencies=NA: only Imports + Depends, skips Suggests
# - doParallel/foreach pulled in automatically as GGIR Imports
#
# Build-time smoke test: load GGIR and check g.shell.GGIR is exported.
# Fails the build immediately if upstream master is broken or a transitive
# dep is incompatible — prevents shipping a broken image to users.
#
# /etc/ggir-version: stamps installed GGIR version + commit SHA for downstream
# debugging and methods-section provenance.
# -----------------------------------------------------------------------------
RUN install2.r --error --skipinstalled remotes Rcpp unisensR \
 && Rscript -e 'remotes::install_github("wadpac/GGIR", dependencies = NA, upgrade = "never")' \
 && Rscript -e 'suppressMessages(library(GGIR)); stopifnot(exists("g.shell.GGIR")); cat("GGIR", as.character(packageVersion("GGIR")), "loaded OK\n")' \
 && Rscript -e 'd <- packageDescription("GGIR"); sha <- if (is.null(d$RemoteSha)) "NA" else d$RemoteSha; cat(sprintf("%s %s\n", d$Version, sha))' > /etc/ggir-version \
 && rm -rf /tmp/downloaded_packages /tmp/Rtmp*
# -----------------------------------------------------------------------------
# Singularity/Apptainer notes
# - No USER directive: Singularity maps container root to calling user
# - outputdir should be bind-mounted at runtime, not baked into image
# Usage:
#   Docker:      docker run --rm -v /data:/data -v /out:/output \
#                  j262byuu/accelerometer /data/GGIR.R
#   Singularity: apptainer exec ggir.sif Rscript /path/to/GGIR.R
# -----------------------------------------------------------------------------
CMD ["/bin/bash"]
