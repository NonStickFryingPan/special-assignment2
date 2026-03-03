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

echo "Done. Update /YOUR/PATH in pipeline/nextflow.config and scripts/run_benchmark.sh"
