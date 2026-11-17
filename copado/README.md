# Copado Quality Gate — org configuration sources

Everything that builds the **Agentforce Tests - After Commit** quality gate in the **COPADO org** (first green run: 2026-11-17, US-0006701, 87s). These sources target the Copado control org — they are deliberately **outside `force-app/`**, which deploys to the Platform/SIT pipeline orgs. Full design: `docs/agentforce-copado-cicd.md`.

## Live components in the COPADO org

| Component | Record | Source here |
|---|---|---|
| Function `Run_Agentforce_Tests` | `a0lMz00000ef0jOIAQ` — image `copado-multicloud-dx:v6`, timeout 30 min, worker M | script: `../scripts/run_agentforce_tests.sh`; record shape: `record-payloads/function_payload.json` (+`function_current.json` = latest script patch) |
| Function `Agentforce_Deploy` (post-deployment publish + suite gate) | `a0lMz00000efVGvIAM` — same image/timeout/worker; sessionID/endpointID default to `{$Destination.Credential.*}` | script: `../scripts/agentforce_deploy.sh`; record shape: `record-payloads/deploy_function_payload.json`. Attach per user story as a **post-deployment Function step** (same pattern as flow_activation) with params `phase=post`, `agent_api_name=<Agent>`, `test_suite_api_name=<Agent>_Suite`. Not yet exercised by a live promotion. |
| Job Template `Run_Agentforce_Tests_1` | `a0uMz00000SddEHIAZ` (Custom, v1) | `record-payloads/jt_payload.json` |
| Job Step "Run Agentforce Testing Center" | `a0tMz000014nLEzIAM` (Function step) | `record-payloads/step_payload.json` (+`jobstep_current.json` = current ConfigJson) |
| Test Tool `AgentTest` (custom metadata) | CMDT record | `testtool-cmdt/` (deploy: `sf project deploy start --metadata-dir copado/testtool-cmdt -o COPADO`) |
| `AgentTest` picklist value | `copado__Test_Tool` global value set | `test-tool-gvs/` (same deploy pattern; retrieve fresh first — it replaces the whole set) |
| Extension Configuration `AgentforceAgentTest` | `a0fMz00000HDcVVIA1` (user-created, Active, Functional Test) | `record-payloads/extconf_patch.json` |
| Quality Gate Rule + Condition | `a28Mz000003G9aHIAS` / `a27Mz000003w7VdIAI` — After Commit, pipeline AldarProperties, env Platform, filter `{$Changes.Type.equals("AiAuthoringBundle")}` | `record-payloads/qgr_payload.json`, `qgrc_payload.json` |

To modify the function script: edit `../scripts/run_agentforce_tests.sh`, then PATCH `copado__Function__c.copado__Script__c` (see `function_current.json` for the payload shape).

## Other contents

- `apex-expression-unused/` — a fully designed alternative detection (`copado.ParameterExpressionCallable` class returning committed agent names from User Story Metadata). **Never deployed** — the documented `copado --downloadfiles` manifest path made it unnecessary. Keep as plan B.
- `tools/watch_je.sh` — local helper: polls a Job Execution to terminal status, then prints its Result and function log (edit the JE_ID inside).
- `record-payloads/retrieve_*.xml` — manifests used to retrieve the managed GVS/field definitions.

## The conventions the gate enforces

1. Every Agentforce agent ships with a Testing Center suite named **`<AgentApiName>_Suite`** in the dev sandbox (spec source: `specs/`, generated metadata: `force-app/main/default/aiEvaluationDefinitions/` — commit it with the agent).
2. A committed agent without its suite **fails the gate**; pass threshold is 80% `output_validation` per suite.
3. Platform gotchas learned building this (timeout units, image choice, SOAP endpoints, manifest filename, `provider` for git): see `docs/agentforce-copado-cicd.md` and the team's memory stores.
