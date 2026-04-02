# =============================================================================
# GGIR Docker Image
# Base: rocker/r-ver (Ubuntu-based, minimal, version-locked)
# Target: batch processing on HPC (Singularity/Apptainer compatible)
# GGIR source: GitHub release tag (wadpac/GGIR)
# Parallel: foreach + doParallel (fork-based, no extra system deps needed)
# BLAS/LAPACK: Intel MKL (Math Kernel Library) for hardware acceleration
# =============================================================================
FROM rocker/r-ver:4.5.3

LABEL maintainer="j262byuu@gmail.com" \
      description="GGIR for batch accelerometer data processing with Intel MKL"

# -----------------------------------------------------------------------------
# MKL & Threading Environment Variables (CRITICAL FOR GGIR)
# Restrict MKL to 1 thread per R process to prevent CPU oversubscription.
# GGIR handles its own parallelization via doParallel (spawning multiple R processes).
# If MKL also attempts to multithread vector operations inside each process, 
# it will lead to severe thread contention and crash the performance.
# -----------------------------------------------------------------------------
ENV MKL_NUM_THREADS=1
ENV OMP_NUM_THREADS=1
ENV MKL_THREADING_LAYER=GNU

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
 && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# R packages
# - remotes: needed to install from GitHub
# - GGIR: pinned to latest commit at master
# - dependencies=NA: only Imports + Depends, skips Suggests
#   (knitr, rmarkdown, testthat, covr, actilifecounts, readxl not needed)
# - doParallel/foreach pulled in automatically as GGIR Imports
# -----------------------------------------------------------------------------
RUN install2.r --error --skipinstalled remotes \
 && Rscript -e 'remotes::install_github("wadpac/GGIR", dependencies = NA, upgrade = "never")' \
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