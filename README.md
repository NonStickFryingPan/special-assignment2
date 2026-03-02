```markdown
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

### Subsetting

The full FASTQ (3.4 GB, 138,688 reads) was subsampled to a quarter for this coursework:

```bash
head -n 138688 m54238_180901_011437.Q20.fastq > HG002_subset_quarter.fastq
# 34,672 reads · 851 MB
```

> ⚠️ Low coverage (~3–4×) is the primary driver of reduced recall in the benchmarking results. At standard depth (≥15×) both tools are expected to achieve SNP F1 > 0.98.

---

## Pipeline

```
PacBio HiFi FASTQ
       │
       ▼
┌──────────────────┐
│ CHECK_CONTAINERS │  Preflight: verify all Singularity images
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│    MINIMAP2      │  map-hifi preset · 2-pass (index then align)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   SORT_INDEX     │  samtools sort + index
└────────┬─────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌────────┐ ┌───────────┐
│ CLAIR3 │ │DEEPVARIANT│   Both run in parallel on the BAM
│ (hifi) │ │ (PACBIO)  │
└────────┘ └───────────┘
         │
         ▼
┌──────────────────┐
│  run_benchmark   │  hap.py vs GIAB HG002 v4.2.1 (separate SLURM job)
│      .sh         │
└──────────────────┘
```

### Containers

| Container | Image | Purpose |
|-----------|-------|---------|
| minimap2 | `staphb/minimap2:2.28` | HiFi read alignment |
| samtools | `staphb/samtools:1.21` | BAM sort + index |
| Clair3 | `hkubal/clair3:latest` | Long-read variant calling |
| DeepVariant | `google/deepvariant:1.6.1` | CNN-based variant calling |
| hap.py | `pkrusche/hap.py:latest` | Truth-set benchmarking |

---

## Repository Layout

```
variant-calling-pipeline/
├── pipeline/
│   ├── main.nf               # Nextflow DSL2 workflow
│   └── nextflow.config       # SLURM + Singularity configuration
├── scripts/
│   ├── download_data.sh      # Download all inputs (reads, ref, GIAB)
│   └── run_benchmark.sh      # SLURM job: hap.py benchmarking
├── results/                  # Created at runtime — not committed
│   ├── alignment/
│   │   ├── HG002.sorted.bam
│   │   └── HG002.sorted.bam.bai
│   ├── clair3/
│   │   ├── HG002.clair3.vcf.gz
│   │   └── HG002.clair3.vcf.gz.tbi
│   ├── deepvariant/
│   │   ├── HG002.deepvariant.vcf.gz
│   │   └── HG002.deepvariant.vcf.gz.tbi
│   └── benchmark/
│       ├── clair3/
│       └── deepvariant/
└── README.md
```

> Large files (BAM, VCF, reference genome, containers) are excluded and must be downloaded separately.

---

## Pipeline Files

### `pipeline/main.nf`

```groovy
nextflow.enable.dsl = 2

if ( !params.reference )  error "Missing --reference"
if ( !params.reads )      error "Missing --reads"
if ( !params.model_path ) error "Missing --model_path"

process CHECK_CONTAINERS {
    executor 'local'
    output: val true
    script:
    """
    apptainer exec ${params.minimap2_img} minimap2 --version || exit 1
    apptainer exec ${params.samtools_img} samtools --version || exit 1
    apptainer exec ${params.clair3_img} run_clair3.sh --version || exit 1
    apptainer exec ${params.deepvariant_img} /opt/deepvariant/bin/run_deepvariant --version || exit 1
    echo "[CHECK] All containers OK."
    """
}

process MINIMAP2 {
    container params.minimap2_img
    publishDir "${params.outdir}/alignment", mode: 'copy'
    input: val ready; path reads; path ref
    output: path "${params.sample}.sam"
    script:
    """
    minimap2 -d ${params.sample}.mmi ${ref}
    minimap2 -ax map-hifi -t ${task.cpus} ${params.sample}.mmi ${reads} > ${params.sample}.sam
    """
}

process SORT_INDEX {
    container params.samtools_img
    publishDir "${params.outdir}/alignment", mode: 'copy'
    input: path sam
    output: tuple path("${params.sample}.sorted.bam"), path("${params.sample}.sorted.bam.bai")
    script:
    """
    samtools sort -@ ${task.cpus} -o ${params.sample}.sorted.bam ${sam}
    samtools index ${params.sample}.sorted.bam
    """
}

process CALL_VARIANTS_CLAIR3 {
    container params.clair3_img
    publishDir "${params.outdir}/clair3", mode: 'copy'
    input:
    val  ready
    tuple path(bam), path(bai)
    path ref_fa
    path ref_fai
    val  sample
    output: tuple path("${sample}.clair3.vcf.gz"), path("${sample}.clair3.vcf.gz.tbi")
    script:
    """
    run_clair3.sh \
        --bam_fn=${bam} \
        --ref_fn=${ref_fa} \
        --threads=${task.cpus} \
        --platform=hifi \
        --model_path=${params.model_path} \
        --output=clair3_tmp \
        --include_all_ctgs
    cp clair3_tmp/merge_output.vcf.gz     ${sample}.clair3.vcf.gz
    cp clair3_tmp/merge_output.vcf.gz.tbi ${sample}.clair3.vcf.gz.tbi
    """
}

process CALL_VARIANTS_DEEPVARIANT {
    container params.deepvariant_img
    publishDir "${params.outdir}/deepvariant", mode: 'copy'
    input:
    val  ready
    tuple path(bam), path(bai)
    path ref_fa
    path ref_fai
    val  sample
    output: tuple path("${sample}.deepvariant.vcf.gz"), path("${sample}.deepvariant.vcf.gz.tbi")
    script:
    """
    /opt/deepvariant/bin/run_deepvariant \
        --model_type=PACBIO \
        --ref=${ref_fa} \
        --reads=${bam} \
        --output_vcf=${sample}.deepvariant.vcf.gz \
        --num_shards=${task.cpus}
    """
}

workflow {
    ref_ch     = Channel.value(file(params.reference))
    ref_fai_ch = Channel.value(file("${params.reference}.fai"))
    ready      = CHECK_CONTAINERS()

    bam_file = file("${params.outdir}/alignment/${params.sample}.sorted.bam")
    bai_file = file("${params.outdir}/alignment/${params.sample}.sorted.bam.bai")

    if (bam_file.exists() && bai_file.exists()) {
        log.info "BAM found — skipping alignment"
        bam_ch = Channel.value([bam_file, bai_file])
    } else {
        reads_ch = Channel.fromPath(params.reads)
        sam_ch   = MINIMAP2(ready, reads_ch, ref_ch)
        bam_ch   = SORT_INDEX(sam_ch)
    }

    CALL_VARIANTS_CLAIR3(ready, bam_ch, ref_ch, ref_fai_ch, params.sample)
    CALL_VARIANTS_DEEPVARIANT(ready, bam_ch, ref_ch, ref_fai_ch, params.sample)
}
```

### `pipeline/nextflow.config`

```groovy
singularity {
    enabled          = true
    autoMounts       = true
    pullTimeout      = '2h'
    cacheDir         = "/YOUR/PATH/work/singularity"           // ← UPDATE
    containerOptions = "--bind /YOUR/SCRATCH:/YOUR/SCRATCH"    // ← UPDATE
}

process {
    executor      = 'slurm'
    queue         = 'gpu'
    cpus          = 8
    memory        = '32 GB'
    time          = '24:00:00'
    errorStrategy = 'retry'
    maxRetries    = 1

    withName: CALL_VARIANTS_DEEPVARIANT {
        memory = '64 GB'
    }
}

params {
    sample     = "HG002"
    reads      = "/YOUR/PATH/data/HG002_subset_quarter.fastq"                      // ← UPDATE
    reference  = "/YOUR/PATH/ref/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna"  // ← UPDATE
    model_path = "/opt/models/hifi"
    outdir     = "/YOUR/PATH/results"                                               // ← UPDATE

    minimap2_img    = "/YOUR/PATH/work/singularity/staphb-minimap2-2.28.img"       // ← UPDATE
    samtools_img    = "/YOUR/PATH/work/singularity/staphb-samtools-1.21.img"       // ← UPDATE
    clair3_img      = "/YOUR/PATH/work/singularity/hkubal-clair3-latest.img"       // ← UPDATE
    deepvariant_img = "/YOUR/PATH/work/singularity/google-deepvariant-1.6.1.img"   // ← UPDATE
}
```

### `scripts/run_benchmark.sh`

```bash
#!/bin/bash
#SBATCH --job-name=happy_benchmark
#SBATCH --output=/YOUR/PATH/results/benchmark_%j.log
#SBATCH --error=/YOUR/PATH/results/benchmark_%j.err
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=04:00:00
#SBATCH --mem=32G

BASE=/YOUR/PATH   # ← UPDATE THIS

HAPPY=$BASE/work/singularity/happy.img
REF=$BASE/ref/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna
GIAB_VCF=$BASE/giab/HG002_GRCh38_1_22_v4.2.1_benchmark.vcf.gz
GIAB_BED=$BASE/giab/HG002_GRCh38_1_22_v4.2.1_benchmark_noinconsistent.bed

mkdir -p $BASE/results/benchmark/clair3
mkdir -p $BASE/results/benchmark/deepvariant

echo "[HAP.PY] Benchmarking Clair3..."
apptainer exec --bind /YOUR/SCRATCH:/YOUR/SCRATCH $HAPPY \
    /opt/hap.py/bin/hap.py \
    $GIAB_VCF \
    $BASE/results/clair3/HG002.clair3.vcf.gz \
    -f $GIAB_BED \
    -r $REF \
    -o $BASE/results/benchmark/clair3/HG002.clair3.happy \
    --engine=vcfeval \
    --threads=8

echo "[HAP.PY] Benchmarking DeepVariant..."
apptainer exec --bind /YOUR/SCRATCH:/YOUR/SCRATCH $HAPPY \
    /opt/hap.py/bin/hap.py \
    $GIAB_VCF \
    $BASE/results/deepvariant/HG002.deepvariant.vcf.gz \
    -f $GIAB_BED \
    -r $REF \
    -o $BASE/results/benchmark/deepvariant/HG002.deepvariant.happy \
    --engine=vcfeval \
    --threads=8

echo "DONE"
```

### `scripts/download_data.sh`

```bash
#!/bin/bash
# Usage: bash download_data.sh /path/to/target/dir
TARGET=${1:-.}
mkdir -p $TARGET/{data,ref,giab}

echo "[1/3] Downloading HG002 HiFi reads..."
wget -P $TARGET/data \
    https://s3-us-west-2.amazonaws.com/human-pangenomics/NHGRI_UCSC_panel/HG002/hpp_HG002_NA24385_son_v1/PacBio_HiFi/15kb/m54238_180901_011437.Q20.fastq

echo "Subsetting to quarter..."
head -n 138688 $TARGET/data/m54238_180901_011437.Q20.fastq \
    > $TARGET/data/HG002_subset_quarter.fastq
rm $TARGET/data/m54238_180901_011437.Q20.fastq

echo "[2/3] Downloading GRCh38 reference..."
wget -P $TARGET/ref \
    https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/000/001/405/GCA_000001405.15_GRCh38/seqs_for_alignment_pipelines.ucsc_ids/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz
gunzip $TARGET/ref/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz

echo "[3/3] Downloading GIAB HG002 v4.2.1 truth set..."
GIAB=https://ftp-trace.ncbi.nlm.nih.gov/giab/ftp/release/AshkenazimTrio/HG002_NA24385_son/NISTv4.2.1/GRCh38
wget -P $TARGET/giab $GIAB/HG002_GRCh38_1_22_v4.2.1_benchmark.vcf.gz
wget -P $TARGET/giab $GIAB/HG002_GRCh38_1_22_v4.2.1_benchmark.vcf.gz.tbi
wget -P $TARGET/giab $GIAB/HG002_GRCh38_1_22_v4.2.1_benchmark_noinconsistent.bed

echo "Done. Update /YOUR/PATH in pipeline/nextflow.config and scripts/run_benchmark.sh before running."
```

---

## Reproducing the Pipeline

### Prerequisites

- HPC cluster with SLURM and Singularity/Apptainer (≥ 3.5)
- Nextflow (≥ 22.10)
- GPU partition available
- ~25 GB scratch space

### Step 1 — Clone

```bash
git clone https://github.com/YOUR_USERNAME/variant-calling-pipeline.git
cd variant-calling-pipeline
```

### Step 2 — Download input data

```bash
bash scripts/download_data.sh /your/target/directory
```

### Step 3 — Pull containers

```bash
SDIR=/your/path/work/singularity && mkdir -p $SDIR

apptainer pull $SDIR/staphb-minimap2-2.28.img     docker://staphb/minimap2:2.28
apptainer pull $SDIR/staphb-samtools-1.21.img     docker://staphb/samtools:1.21
apptainer pull $SDIR/hkubal-clair3-latest.img     docker://hkubal/clair3:latest
apptainer pull $SDIR/google-deepvariant-1.6.1.img docker://google/deepvariant:1.6.1
apptainer pull $SDIR/happy.img                    docker://pkrusche/hap.py:latest
```

### Step 4 — Update paths

Replace all `/YOUR/PATH` placeholders in `pipeline/nextflow.config` and `scripts/run_benchmark.sh`.

### Step 5 — Run variant calling

```bash
screen -S pipeline
nextflow run pipeline/main.nf -c pipeline/nextflow.config
```

### Step 6 — Run benchmarking

```bash
sbatch scripts/run_benchmark.sh
```

Results land in `results/benchmark/clair3/` and `results/benchmark/deepvariant/` as `*.summary.csv`.

---

## Results

> Benchmarked against GIAB HG002 v4.2.1 | Reference: GRCh38 | Tool: hap.py (vcfeval engine) | Regions: chr1–22 high-confidence BED

### SNP Performance

| Tool | Recall | Precision | F1 Score |
|------|--------|-----------|----------|
| **Clair3** | — | — | — |
| **DeepVariant** | — | — | — |

### INDEL Performance

| Tool | Recall | Precision | F1 Score |
|------|--------|-----------|----------|
| **Clair3** | — | — | — |
| **DeepVariant** | — | — | — |

> Results will be updated once benchmarking completes.

---

## Challenges

**1. Compute node filesystem isolation**
`/shared/` was accessible from the master node but not SLURM compute nodes, causing `exit 255 — lstat /shared: no such file or directory`. Fixed by pulling all containers to the project scratch filesystem.

**2. BAM index timestamp mismatch**
The `.bai` had an older timestamp than the `.bam`, causing both callers to reject it with `index file is older than data file`. Fixed with `touch HG002.sorted.bam.bai`.

**3. Reference `.fai` not staged in work directory**
Nextflow only stages files explicitly declared as `path` inputs. Both callers require the `.fai` co-located with the `.fna`. Fixed by adding `path ref_fai` as an explicit input to both variant calling processes.

**4. Container pull failures**
Several Docker Hub images timed out or returned access denied. Resolved by switching to `staphb/` images and setting `pullTimeout = '2h'`.

**5. SLURM job timeouts (exit 143)**
Wall-time limits were too short. DeepVariant `make_examples` alone took ~2 hours on the ¼ subset. Resolved by setting `time = '24:00:00'`.

---

## Requirements

| Tool | Version |
|------|---------|
| Nextflow | ≥ 22.10 |
| Singularity / Apptainer | ≥ 3.5 |
| SLURM | any |
| minimap2 | 2.28 |
| samtools | 1.21 |
| Clair3 | latest |
| DeepVariant | 1.6.1 |
| hap.py | latest |

---

## References

1. Poplin R et al. (2018). A universal SNP and small-indel variant caller using deep neural networks. *Nature Biotechnology*, 36, 983–987. — **DeepVariant**
2. Zheng Z et al. (2022). Symphonizing pileup and full-alignment for deep learning-based long-read variant calling. *Nature Computational Science*, 2, 797–803. — **Clair3**
3. Krusche P et al. (2019). Best practices for benchmarking germline small-variant calls in human genomes. *Nature Biotechnology*, 37, 555–560. — **hap.py**
4. Zook JM et al. (2020). An open resource for accurately benchmarking small variant and reference calls. *Nature Biotechnology*, 38, 1347–1355. — **GIAB**
5. Kurtzer GM et al. (2017). Singularity: Scientific containers for mobility of compute. *PLOS ONE*, 12(5). — **Singularity**

---

<div align="center">

**Course:** BI-436 Special Topics in Bioinformatics &nbsp;|&nbsp; **Assignment #1**

*Nextflow · Clair3 · DeepVariant · GIAB · SLURM · Singularity · GRCh38 · hap.py*

</div>
```
