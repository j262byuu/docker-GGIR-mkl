# docker-GGIR-mkl

A hardware-accelerated Docker image for GGIR (j262byuu/accelerometer). Optimized for high-throughput batch processing on HPC.

## 🙏 Acknowledgements / 致谢

First and foremost, profound thanks to **Vincent van Hees** and the entire [wadpac](https://github.com/wadpac) community. The original [GGIR R package](https://wadpac.github.io/GGIR/) is a NOVEL contribution to actigraphy and public health data science. This Docker image is merely a hardware-optimized wrapper built entirely upon their incredible foundational work. 

When using this image, **please ensure you cite the original GGIR publications** (doi: 10.5281/zenodo.18798867).

---

## ⚡ Quick Start

### Docker (Local / Cloud VMs)
```bash
docker run --rm \
  -v /your/data:/data \
  -v /your/output:/output \
  j262byuu/accelerometer:04022026 \
  Rscript /data/GGIR.R
```

### Singularity / Apptainer (HPC Clusters)
```bash
# 1. Pull the image
apptainer pull ggir.sif docker://j262byuu/accelerometer:04022026

# 2. Execute on compute node (remember to bind mount your directories)
apptainer exec -B /your/data:/data -B /your/output:/output ggir.sif Rscript /data/GGIR.R
```

---

## 🏷 Available Tags

* **`tag 04022026` (Latest):** Hardware-accelerated version! Integrated **Intel MKL** as the default BLAS/LAPACK backend. This significantly speeds up matrix-heavy operations like auto-calibration (`g.calibrate`) and vector math. By default, `MKL_NUM_THREADS` is locked to 1 (you can manually bypass this via docker parameters) to prevent thread contention during GGIR's native file-level parallelization.
* **`tag 03262026`:** Rebuilt from scratch using a minimal Dockerfile (now open source). Base image upgraded to `rocker/r-ver:4.5.3`. `mMARCH.AC` dropped. Image size reduced from 4.36 GB to 1.8 GB. GGIR pinned to 3.3-4.
* **`tag 03092026`:** Updated GGIR to 3.3.4. Updated `mMARCH.AC` to 3.3.4.0. *Note: I recommend stopping use of any version prior to 3.2.7 due to a start time bug ([issue #1311](https://github.com/wadpac/GGIR/issues/1311)). This affects both part 5 and 6.*
* **`tag 10142025`:** Updated GGIR to 3.3.1. Urgent fix for part 6 failures when multithreading is enabled.
* **`tag 09182025`:** Updated GGIR to 3.3.0. The new auto-correct sleep guider is a notable addition.
* **`tag 07242025`:** Updated GGIR to 3.2.9. Docker image was flattened to reduce size.

### Archived Tags
The following tags have been removed from this repository because they are old versions. They are listed here for reference only:
* `tag 05022025`: GGIR 3.2.6. Sleep regularity index (comparable to sleepreg) was introduced.
* `tag 01112025`: GGIR 3.1.10.
* `tag 12042024`: GGIR 3.1.7. Notable addition of `part2_eventsummary.csv`.
* `tag 11152024`: GGIR 3.1.6 (GitHub-only release; nonwear_range_threshold was reset to 150).
* `tag 10112024`: Added fields for image.plot in module 5 and system-level pandoc for Rmd files.
* `tag 09172024`: Added rmarkdown and r.jive.
* `tag 09132024`: GGIR 3.1.4 and mMARCH.AC 2.9.4.0. Fixed `read.xlsx` errors.

---

## 🗺 Future Roadmap: Pushing the Limits

My goal is to systematically eliminate bottlenecks in CPU math, memory bandwidth, and I/O for massive-scale actigraphy pipelines.

* [x] **Phase 1: CPU Math Saturation.** Replaced native R BLAS/LAPACK with Intel MKL.
* [ ] **Phase 2: Rcpp Memory Optimization for ENMO.** Replacing GGIR's native `cumsum` epoch aggregation with a zero-allocation sliding window algorithm in C++ (`Rcpp`) to eliminate RAM bandwidth choking.
* [ ] **Phase 3: Zero-Overhead Data I/O.** Developing an external preprocessing pipeline to strip text-based time-column parsing entirely before data hits GGIR.

---

## 📬 Contact
Fell free to reach me at LinkedIn

为了安全我锁死了 MKL 的线程数。欢迎研究者联系交流，直接 LinkedIn 加我就行，当然给我发email我也欢迎
