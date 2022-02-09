#!/usr/bin/env nextflow

/*
 * Main alignment work flow.
 */

nextflow.enable.dsl = 2

include { validatePipeline } from './functions/validation'
include { parse } from './processes/1_parse'
include { sizeAnnotation } from './processes/2_size_annotation'
include { outlierSuppression } from './processes/3_outlier_suppression'
include { detection } from './processes/4_detection'
include { analysis } from './processes/5_analysis'

/*
 * Check the pipeline is set up without basic errors.
 */
if (!validatePipeline(params))
{
    exit 1
}

/*
 * Main work flow.
 */
workflow
{
    tumourMutationsChannel = channel.fromPath(params.TUMOUR_MUTATIONS_CSV, checkIfExists: true)
    layoutChannel = channel.fromPath(params.LAYOUT_TABLE, checkIfExists: true)

    bamChannel = channel.fromPath(params.INPUT_FILES, checkIfExists: true)
        .splitCsv(header: true, by: 1, strip: true)
        .map {
            row ->
            bam = file(row.FILE_NAME, checkIfExists: true)
            index = file("${bam}.bai") // The index file may or may not exist.
            tuple row.POOL, row.BARCODE, bam, index
        }

    parse(bamChannel, tumourMutationsChannel, layoutChannel)

    sizeAnnotation(bamChannel, parse.out.onTargetMutationsFile, tumourMutationsChannel)

    outlierSuppression(parse.out.onTargetMutationsFile, sizeAnnotation.out.mutationsFiles)

    detection(outlierSuppression.out.perSampleMutationsFiles, outlierSuppression.out.sizeCharacterisationFile)

    analysis(outlierSuppression.out.mutationsFile,
             layoutChannel,
             parse.out.onTargetErrorRatesFile,
             parse.out.offTargetErrorRatesNoCosmic,
             detection.out.invarScores)
}
