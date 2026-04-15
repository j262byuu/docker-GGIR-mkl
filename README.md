# docker-GGIR

A Docker image for [GGIR](https://wadpac.github.io/GGIR/) accelerometer data processing (`j262byuu/accelerometer`), optimized for high-throughput batch processing on HPC clusters.

## Acknowledgements

This image is built entirely upon the [GGIR R package](https://wadpac.github.io/GGIR/) by **Vincent van Hees** and the [wadpac](https://github.com/wadpac) community. GGIR is a foundational contribution to actigraphy and physical activity research.

When using this image, **please cite the original GGIR publications** (doi: 10.5281/zenodo.1051064).

## Quick Start

**Docker (Local / Cloud VMs)**

```bash
docker run --rm \
  -v /your/data:/data \
  -v /your/output:/output \
  j262byuu/accelerometer:04152026 \
  Rscript /data/GGIR.R
```

**Singularity / Apptainer (HPC Clusters)**

```bash
# Pull the image
apptainer pull ggir.sif docker://j262byuu/accelerometer:04152026

# Execute on compute node
apptainer exec \
  -B /your/data:/data \
  -B /your/output:/output \
  ggir.sif Rscript /data/GGIR.R
```

## Available Tags

**`04152026` (Latest)** — Rcpp pre-installed for compatibility with the [Rcpp-optimized GGIR fork](https://github.com/j262byuu/GGIR/tree/feature/rcpp-enmo). Intel MKL as default BLAS/LAPACK backend. GGIR installed from official upstream (wadpac/GGIR). `MKL_NUM_THREADS` locked to 1 by default to prevent thread contention during GGIR's file-level parallelization. UTF-8 locale set for timestamp parsing edge cases.

**`04022026`** — Intel MKL integrated. GGIR from official upstream.

**`03262026`** — Rebuilt from scratch with a minimal Dockerfile. Base image upgraded to `rocker/r-ver:4.5.3`. `mMARCH.AC` dropped. Image size reduced from 4.36 GB to 1.8 GB. GGIR pinned to 3.3-4.

**`03092026`** — GGIR 3.3.4. Updated `mMARCH.AC` to 3.3.4.0. Note: avoid versions prior to 3.2.7 due to a start time bug ([issue #1311](https://github.com/wadpac/GGIR/issues/1311)) affecting parts 5 and 6.

**`10142025`** — GGIR 3.3.1. Fix for part 6 failures with multithreading enabled.

**`09182025`** — GGIR 3.3.0. Added auto-correct sleep guider.

**`07242025`** — GGIR 3.2.9. Docker image flattened to reduce size.

<details>
<summary>Archived Tags</summary>

These tags have been removed from the registry. Listed for reference only.

- `05022025`: GGIR 3.2.6. Sleep regularity index introduced.
- `01112025`: GGIR 3.1.10.
- `12042024`: GGIR 3.1.7. Added `part2_eventsummary.csv`.
- `11152024`: GGIR 3.1.6 (GitHub-only; nonwear_range_threshold reset to 150).
- `10112024`: Added image.plot fields in module 5 and system-level pandoc.
- `09172024`: Added rmarkdown and r.jive.
- `09132024`: GGIR 3.1.4 and mMARCH.AC 2.9.4.0.

</details>

## Performance Optimization Roadmap

Systematic profiling of GGIR Part 1 on a 251 MB Axivity CWA file (7-day, 100Hz) revealed the following time distribution:

| Component | Time | Share |
|---|---|---|
| `GGIRread::readAxivity` (I/O + CWA parsing) | 337 s | 75% |
| `g.applymetrics` (ENMO epoch aggregation) | 33 s | 7% |
| `g.calibrate` (auto-calibration) | 5.7 s | 1% |
| Other (non-wear detection, data management) | 76 s | 17% |
| **Total** | **451 s** | |

### Phase 1: Intel MKL ✅

Replaced default R BLAS/LAPACK with Intel MKL. After profiling GGIR's source code, I confirmed that GGIR's core computations (ENMO, epoch aggregation, non-wear detection) are element-wise vector operations that do not call BLAS. The `g.calibrate` ellipsoid fitting uses `lm.wfit` (QR decomposition), but on matrices of only 3 columns, too small for MKL to make a measurable difference. MKL remains in the image for downstream R workflows (mixed-effects models, PCA, large-scale regression) that do benefit from optimized linear algebra.

### Phase 2: Fused Rcpp ENMO Path ✅ (validated, pending upstream merge)

Replaced `g.applymetrics`' ENMO computation chain (`EuclideanNorm` -> subtract -> clamp -> `cumsum`-based epoch averaging) with a single-pass C++ implementation (`enmoFusedCpp`). Fork: [j262byuu/GGIR@feature/rcpp-enmo](https://github.com/j262byuu/GGIR/tree/feature/rcpp-enmo). Not yet included in the Docker image; will be integrated after upstream merge or when stability is fully confirmed. To use it now:

```r
remotes::install_github("j262byuu/GGIR@feature/rcpp-enmo", dependencies = NA, upgrade = "never")
```

Benchmarked on simulated 7-day 100Hz data (60.5M samples):

| Metric | Original R | Rcpp | Improvement |
|---|---|---|---|
| Time per call | 10.16 s | 1.45 s | **7.0x faster** |
| Peak memory | 6,597 MB | 2,806 MB | **57% less** |
| Correctness | Reference | max diff < 1e-11 | **PASS** |
| NA handling | cumsum propagates NA forward | NA limited to affected epoch | **Improved** |

The implementation accepts a `NumericMatrix` (zero-copy from R) rather than three separate column vectors, trading a small amount of speed (7x vs 8.6x with separate vectors) for less memory allocation at the R call boundary.

The primary value of this optimization is **memory reduction in parallel processing**. Each worker saves ~3.8 GB of transient allocations, allowing more concurrent workers on HPC nodes.

Note: end-to-end Part 1 speedup is modest because ENMO computation accounts for only 7% of total runtime. The dominant bottleneck is CWA/CSV file I/O (75%), which is addressed in Phase 3.

### Phase 3: CWA Reader Acceleration 🔧

Targeting `GGIRread::readAxivity`, which accounts for 75% of Part 1 runtime. Profiling breakdown:

- `readBin` (R-level binary I/O): 77.5 s, 490K R function calls for per-block reading
- `readDataBlock` (block parsing loop): 67.6 s, per-block header/checksum/unpack in R
- `resample` (interpolation to uniform grid): 26.9 s, already C-implemented in GGIRread
- `timestampDecoder` + `AxivityNumUnpack` + bit operations: 20 s

A C prototype replacing the per-block R loop with a single-pass C parser achieved **6.1x speedup** (176 s -> 29 s) on a 251 MB CWA file. Correctness validation is in progress. This work targets the GGIRread package (separate from GGIR).

Additionally, Part 1 reads each file twice (`g.calibrate` + `g.getmeta`), which doubles I/O cost. A single-read architecture could further halve I/O time.

## Contact

Feel free to reach out on [LinkedIn](https://www.linkedin.com/in/xiaoyu-zong-0a733ba0/)

欢迎研究者联系交流，LinkedIn 加我或者发邮件都可以。
