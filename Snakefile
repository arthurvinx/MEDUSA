from os.path import join

# input args
preprocessingDIR = "Protocol/data"
inputDIR = join(preprocessingDIR, "raw")
phredQuality = "20"
trimmedDIR = join(preprocessingDIR, "trimmed")
removalDIR = join(preprocessingDIR, "removal")
referenceDIR = join(removalDIR, "reference")
ensemblRelease = "101"
bowtie2IndexDIR = join(removalDIR, "index")
assembledDIR = join(preprocessingDIR, "assembled")
collapsedDIR = join(preprocessingDIR, "collapsed")

# env created at .snakemake/conda
env = "envs/protocolMeta.yaml"

IDs = glob_wildcards(join(inputDIR,
    "{id, [A-Za-z0-9]+}{suffix, (_[1-2])?}.fastq"))

ruleorder: qualityControlPaired > qualityControlSingle
ruleorder: removeHumanContaminantsPaired > removeHumanContaminantsSingle

rule all:
    input:
        expand(join(collapsedDIR, "{id}_collapsed.fasta"), id = IDs.id)

rule qualityControlSingle:
    input: join(inputDIR, "{id}.fastq")
    output:
        trimmed = "{trimmedDIR}/{id}_trim.fastq",
        html = "{trimmedDIR}/{id}_report.html",
        json = "{trimmedDIR}/{id}_report.json"
    conda: env
    threads: workflow.cores
    shell: "fastp -i {input} -o {output.trimmed} -q {phredQuality} \
        -w {threads} -h {output.html} -j {output.json}"

rule qualityControlPaired:
    input:
        f = join(inputDIR, "{id}_1.fastq"),
        r = join(inputDIR, "{id}_2.fastq"),
    output:
        f = "{trimmedDIR}/{id}_1_trim.fastq",
        r = "{trimmedDIR}/{id}_2_trim.fastq",
        html = "{trimmedDIR}/{id}_report.html",
        json = "{trimmedDIR}/{id}_report.json"
    conda: env
    threads: workflow.cores
    shell: "fastp -i {input.f} -I {input.r} -o {output.f} \
        -O {output.r} -q {phredQuality} -w {threads} \
        --detect_adapter_for_pe -h {output.html} -j {output.json}"

rule downloadHumanPrimaryAssembly:
    output: "{referenceDIR}/Homo_sapiens.GRCh38.dna.primary_assembly.fa"
    conda: env
    threads: workflow.cores
    shell: "wget -P {referenceDIR} \
    ftp://ftp.ensembl.org/pub/release-{ensemblRelease}/fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz \
    && pigz -d {output} -p {threads}"

rule bowtie2BuildHumanIndex:
    input: join(referenceDIR, "Homo_sapiens.GRCh38.dna.primary_assembly.fa")
    output:
        expand("{indexDIR}/hostHS.{index}.{bt2extension}", index = range(1, 5), bt2extension = ["bt2", "bt2l"], indexDIR = bowtie2IndexDIR),
        expand("{indexDIR}/hostHS.rev.{index}.{bt2extension}", index = range(1, 3), bt2extension = ["bt2", "bt2l"], indexDIR = bowtie2IndexDIR)
    params: indexPrefix = join(bowtie2IndexDIR, "hostHS")
    conda: env
    threads: workflow.cores
    shell: "bowtie2-build {input} {params.indexPrefix} --threads {threads}"

rule removeHumanContaminantsSingle:
    input:
        expand("{indexDIR}/hostHS.{index}.{bt2extension}", index = range(1, 5), bt2extension = ["bt2", "bt2l"], indexDIR = bowtie2IndexDIR),
        expand("{indexDIR}/hostHS.rev.{index}.{bt2extension}", index = range(1, 3), bt2extension = ["bt2", "bt2l"], indexDIR = bowtie2IndexDIR),
        trimmed = join(trimmedDIR, "{id}_trim.fastq")
    output: "{removalDIR}/{id}_unaligned.fastq"
    params: indexPrefix = join(bowtie2IndexDIR, "hostHS")
    conda: env
    threads: workflow.cores
    shell: "bowtie2 -x {params.indexPrefix} -U {input.trimmed} -S {removalDIR}/{wildcards.id}.sam -p {threads} \
        && samtools view -bS {removalDIR}/{wildcards.id}.sam > {removalDIR}/{wildcards.id}.bam \
        && samtools view -b -f 4 -F 256 {removalDIR}/{wildcards.id}.bam > {removalDIR}/{wildcards.id}_unaligned.bam \
        && samtools sort -n {removalDIR}/{wildcards.id}_unaligned.bam -o {removalDIR}/{wildcards.id}_unaligned_sorted.bam \
        && samtools bam2fq {removalDIR}/{wildcards.id}_unaligned_sorted.bam > {removalDIR}/{wildcards.id}_unaligned.fastq"

rule removeHumanContaminantsPaired:
    input:
        expand("{indexDIR}/hostHS.{index}.{bt2extension}", index = range(1, 5), bt2extension = ["bt2", "bt2l"], indexDIR = bowtie2IndexDIR),
        expand("{indexDIR}/hostHS.rev.{index}.{bt2extension}", index = range(1, 3), bt2extension = ["bt2", "bt2l"], indexDIR = bowtie2IndexDIR),
        f = join(trimmedDIR, "{id}_1_trim.fastq"),
        r = join(trimmedDIR, "{id}_2_trim.fastq")
    output:
        f = "{removalDIR}/{id}_unaligned_1.fastq",
        r = "{removalDIR}/{id}_unaligned_2.fastq"
    params: indexPrefix = join(bowtie2IndexDIR, "hostHS")
    conda: env
    threads: workflow.cores
    shell: "bowtie2 -x {params.indexPrefix} -1 {input.f} -2 {input.r} -S {removalDIR}/{wildcards.id}.sam -p {threads} \
        && samtools view -bS {removalDIR}/{wildcards.id}.sam > {removalDIR}/{wildcards.id}.bam \
        && samtools view -b -f 12 -F 256 {removalDIR}/{wildcards.id}.bam > {removalDIR}/{wildcards.id}_unaligned.bam \
        && samtools sort -n {removalDIR}/{wildcards.id}_unaligned.bam -o {removalDIR}/{wildcards.id}_unaligned_sorted.bam \
        && samtools bam2fq {removalDIR}/{wildcards.id}_unaligned_sorted.bam > {removalDIR}/{wildcards.id}_unaligned.fastq \
        && cat {removalDIR}/{wildcards.id}_unaligned.fastq | grep '^@.*/1$' -A 3 --no-group-separator > {removalDIR}/{wildcards.id}_unaligned_1.fastq \
        && cat {removalDIR}/{wildcards.id}_unaligned.fastq | grep '^@.*/2$' -A 3 --no-group-separator > {removalDIR}/{wildcards.id}_unaligned_2.fastq"

rule mergePaired:
    input:
        f = join(removalDIR, "{id}_unaligned_1.fastq"),
        r = join(removalDIR, "{id}_unaligned_2.fastq")
    output:
        merged = "{assembledDIR}/{id}_assembled.fastq",
        html = "{assembledDIR}/{id}_report2.html",
        json = "{assembledDIR}/{id}_report2.json"
    conda: env
    threads: workflow.cores
    shell: "fastp -i {input.f} -I {input.r} -o {assembledDIR}/{wildcards.id}_unassembled_1.fastq \
        -O {assembledDIR}/{wildcards.id}_unassembled_2.fastq -q {phredQuality} -w {threads} \
        --detect_adapter_for_pe -h {output.html} -j {output.json} \
        -m --merged_out {output.merged}"

rule deduplicateSingle:
    input: join(removalDIR, "{id}_unaligned.fastq")
    output: "{collapsedDIR}/{id}_collapsed.fasta"
    conda: env
    shell: "fastx_collapser -i {input} -o {output}"

rule deduplicatePaired:
    input: join(assembledDIR, "{id}_assembled.fastq")
    output: "{collapsedDIR}/{id}_collapsed.fasta"
    conda: env
    shell: "fastx_collapser -i {input} -o {output}"

# rule downloadNR:
#     input: join, "")
#     output: ""
#     conda: env
#     threads: workflow.cores
#     shell: ""

# rule diamondMakeDB:
#     input: join, "")
#     output: ""
#     conda: env
#     threads: workflow.cores
#     shell: ""

# rule alignment:
#     input: join, "")
#     output: ""
#     conda: env
#     threads: workflow.cores
#     shell: ""
