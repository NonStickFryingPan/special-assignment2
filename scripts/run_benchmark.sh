#!/bin/bash
#SBATCH --job-name=happy_benchmark
#SBATCH --output=/hdd4/sines/specialtopicsinbioinformatics/luqman.sines/assignment1/results/benchmark_%j.log
#SBATCH --error=/hdd4/sines/specialtopicsinbioinformatics/luqman.sines/assignment1/results/benchmark_%j.err
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=04:00:00
#SBATCH --mem=32G

BASE=/hdd4/sines/specialtopicsinbioinformatics/luqman.sines/assignment1
HAPPY=$BASE/work/singularity/happy.img
REF=$BASE/ref/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna
GIAB_VCF=$BASE/giab/HG002_GRCh38_1_22_v4.2.1_benchmark.vcf.gz
GIAB_BED=$BASE/giab/HG002_GRCh38_1_22_v4.2.1_benchmark_noinconsistent.bed

mkdir -p $BASE/results/benchmark/clair3
mkdir -p $BASE/results/benchmark/deepvariant

# Benchmark Clair3
echo "[HAP.PY] Benchmarking Clair3..."
apptainer exec --bind /hdd4:/hdd4 $HAPPY \
    /opt/hap.py/bin/hap.py \
    $GIAB_VCF \
    $BASE/results/clair3/HG002.clair3.vcf.gz \
    -f $GIAB_BED \
    -r $REF \
    -o $BASE/results/benchmark/clair3/HG002.clair3.happy \
    --engine=vcfeval \
    --threads=8

# Benchmark DeepVariant
echo "[HAP.PY] Benchmarking DeepVariant..."
apptainer exec --bind /hdd4:/hdd4 $HAPPY \
    /opt/hap.py/bin/hap.py \
    $GIAB_VCF \
    $BASE/results/deepvariant/HG002.deepvariant.vcf.gz \
    -f $GIAB_BED \
    -r $REF \
    -o $BASE/results/benchmark/deepvariant/HG002.deepvariant.happy \
    --engine=vcfeval \
    --threads=8

echo "DONE"
