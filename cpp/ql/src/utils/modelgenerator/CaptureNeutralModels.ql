/**
 * @name Capture neutral models.
 * @description Finds neutral models to be used by other queries.
 * @kind diagnostic
 * @id cpp/utils/modelgenerator/neutral-models
 * @tags modelgenerator
 */

import internal.CaptureModels

from DataFlowSummaryTargetApi api, string noflow
where noflow = captureNeutral(api)
select noflow order by noflow
