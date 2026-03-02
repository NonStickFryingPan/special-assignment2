<div align="center">

# 🧬 HG002 Variant Calling Pipeline

**A reproducible HPC pipeline comparing Clair3 and DeepVariant on PacBio HiFi long-read data**

[![Nextflow](https://img.shields.io/badge/Workflow-Nextflow-49A043?style=flat-square&logo=nextflow&logoColor=white)](https://www.nextflow.io/)
[![SLURM](https://img.shields.io/badge/Scheduler-SLURM-0078d4?style=flat-square&logo=linux&logoColor=white)](https://slurm.schedmd.com/)
[![Singularity](https://img.shields.io/badge/Containers-Singularity%2FApptainer-6a0dad?style=flat-square)](https://apptainer.org/)
[![GRCh38](https://img.shields.io/badge/Reference-GRCh38-2ea44f?style=flat-square)](https://www.ncbi.nlm.nih.gov/assembly/GCF_000001405.40/)
[![GIAB](https://img.shields.io/badge/Truth%20Set-GIAB%20HG002%20v4.2.1-orange?style=flat-square)](https://www.nist.gov/programs-projects/genome-bottle)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)

[Overview](#overview) · [Dataset](#dataset) · [Pipeline](#pipeline) · [Results](#results) · [Reproduction](#reproducing-the-pipeline) · [Challenges](#challenges) · [References](#references)

</div>

---

## Overview

This repository contains a complete, reproducible **short variant calling and benchmarking pipeline** for PacBio HiFi sequencing data, built as part of the BI-436 Special Topics in Bioinformatics coursework.

The pipeline uses **Nextflow DSL2** for workflow orchestration, **Singularity/Apptainer** containers for reproducibility, and **SLURM** for HPC job scheduling. Two state-of-the-art deep-learning variant callers are compared head-to-head and benchmarked against the GIAB gold standard:

| Caller | Version | Strategy |
|--------|---------|----------|
| **Clair3** | Latest (HiFi model) | Pileup + full-alignment; phased output; maximises recall |
| **DeepVariant** | v1.6.1 (PACBIO model) | CNN image classifier; maximises precision |

---

## Dataset

| Field | Value |
|-------|-------|
| **Sample** | HG002 / NA24385 (Ashkenazim son, GIAB trio) |
| **Platform** | PacBio HiFi long reads |
| **Source** | [HPRC / NHGRI UCSC Panel](https://s3-us-west-2.amazonaws.com/human-pangenomics/NHGRI_UCSC_panel/HG002/) |
| **Reference** | GRCh38 primary assembly (no alt) |
| **Truth set** | GIAB HG002 v4.2.1 — chr1–22 high-confidence regions |
