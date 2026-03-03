nextflow.enable.dsl = 2

if ( !params.reference )  error "Missing --reference"
if ( !params.reads )      error "Missing --reads"
if ( !params.model_path ) error "Missing --model_path"

// ── PREFLIGHT CHECKS ───────────────────────────────────────────────────────
process CHECK_CONTAINERS {
    executor 'local'

    output:
    val true

    script:
    """
    echo "[CHECK] Verifying containers..."

    apptainer exec ${params.minimap2_img} minimap2 --version \
        || { echo "ERROR: minimap2 container failed"; exit 1; }

    apptainer exec ${params.samtools_img} samtools --version \
        || { echo "ERROR: samtools container failed"; exit 1; }

    apptainer exec ${params.clair3_img} run_clair3.sh --version \
        || { echo "ERROR: clair3 container failed"; exit 1; }

    apptainer exec ${params.deepvariant_img} /opt/deepvariant/bin/run_deepvariant --version \
        || { echo "ERROR: deepvariant container failed"; exit 1; }

    echo "[CHECK] All containers OK."
    """
}

// ── 1. MINIMAP2 ────────────────────────────────────────────────────────────
process MINIMAP2 {
    container params.minimap2_img
    publishDir "${params.outdir}/alignment", mode: 'copy'

    input:
    val  ready
    path reads
    path ref

    output:
    path "${params.sample}.sam"

    script:
    """
    echo "[MINIMAP2] Building index..."
    minimap2 -d ${params.sample}.mmi ${ref}

    echo "[MINIMAP2] Aligning reads with map-hifi..."
    minimap2 -ax map-hifi -t ${task.cpus} ${params.sample}.mmi ${reads} > ${params.sample}.sam

    echo "[MINIMAP2] Done."
    """
}

// ── 2. SORT + INDEX ────────────────────────────────────────────────────────
process SORT_INDEX {
    container params.samtools_img
    publishDir "${params.outdir}/alignment", mode: 'copy'

    input:
    path sam

    output:
    tuple path("${params.sample}.sorted.bam"),
          path("${params.sample}.sorted.bam.bai")

    script:
    """
    echo "[SAMTOOLS] Sorting..."
    samtools sort -@ ${task.cpus} -o ${params.sample}.sorted.bam ${sam}

    echo "[SAMTOOLS] Indexing..."
    samtools index ${params.sample}.sorted.bam

    echo "[SAMTOOLS] Done."
    """
}

// ── 3. CLAIR3 ──────────────────────────────────────────────────────────────
process CALL_VARIANTS_CLAIR3 {
    container params.clair3_img
    publishDir "${params.outdir}/clair3", mode: 'copy'

    input:
    tuple path(bam), path(bai)
    path ref_fa
    path ref_fai
    val  sample

    output:
    tuple path("${sample}.clair3.vcf.gz"),
          path("${sample}.clair3.vcf.gz.tbi")

    script:
    """
    echo "[CLAIR3] Starting variant calling on ${bam}..."
    echo "[CLAIR3] Reference: ${ref_fa}"
    echo "[CLAIR3] Reference index: ${ref_fai}"

    run_clair3.sh \
        --bam_fn=${bam} \
        --ref_fn=${ref_fa} \
        --threads=${task.cpus} \
        --platform=hifi \
        --model_path=${params.model_path} \
        --output=clair3_tmp \
        --include_all_ctgs

    echo "[CLAIR3] Copying outputs..."
    cp clair3_tmp/merge_output.vcf.gz     ${sample}.clair3.vcf.gz
    cp clair3_tmp/merge_output.vcf.gz.tbi ${sample}.clair3.vcf.gz.tbi

    echo "[CLAIR3] Done."
    """
}

// ── 4. DEEPVARIANT ─────────────────────────────────────────────────────────
process CALL_VARIANTS_DEEPVARIANT {
    container params.deepvariant_img
    publishDir "${params.outdir}/deepvariant", mode: 'copy'

    input:
    tuple path(bam), path(bai)
    path ref_fa
    path ref_fai
    val  sample

    output:
    tuple path("${sample}.deepvariant.vcf.gz"),
          path("${sample}.deepvariant.vcf.gz.tbi")

    script:
    """
    echo "[DEEPVARIANT] Starting variant calling on ${bam}..."
    echo "[DEEPVARIANT] Reference: ${ref_fa}"
    echo "[DEEPVARIANT] Reference index: ${ref_fai}"

    /opt/deepvariant/bin/run_deepvariant \
        --model_type=PACBIO \
        --ref=${ref_fa} \
        --reads=${bam} \
        --output_vcf=${sample}.deepvariant.vcf.gz \
        --num_shards=${task.cpus}

    echo "[DEEPVARIANT] Done."
    """
}

// ── WORKFLOW ───────────────────────────────────────────────────────────────
workflow {
    ref_ch     = Channel.value(file(params.reference))
    ref_fai_ch = Channel.value(file("${params.reference}.fai"))

    ready = CHECK_CONTAINERS()

    bam_file = file("${params.outdir}/alignment/${params.sample}.sorted.bam")
    bai_file = file("${params.outdir}/alignment/${params.sample}.sorted.bam.bai")

    if (bam_file.exists() && bai_file.exists()) {
        log.info "BAM found in results — skipping MINIMAP2 and SORT_INDEX"
        bam_ch = Channel.value([bam_file, bai_file])
    } else {
        log.info "BAM not found — running alignment"
        reads_ch = Channel.fromPath(params.reads)
        sam_ch   = MINIMAP2(ready, reads_ch, ref_ch)
        bam_ch   = SORT_INDEX(sam_ch)
    }

    CALL_VARIANTS_CLAIR3(bam_ch, ref_ch, ref_fai_ch, params.sample)
    CALL_VARIANTS_DEEPVARIANT(bam_ch, ref_ch, ref_fai_ch, params.sample)
}
