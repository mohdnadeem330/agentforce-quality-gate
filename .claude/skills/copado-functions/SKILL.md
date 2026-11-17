---
name: copado-functions
description: Use when building, modifying, wiring, or debugging Copado Functions or QIF quality-gate tooling — writing a function script, choosing a function image, passing dynamic expressions, bridging to the sf CLI, registering a custom test tool, or diagnosing failures like "Invalid template name", "Canceled" after exactly 5 minutes, "AuthCodeUsernameRetrievalError"/"405 Only POST allowed", "128: Repository not authenticated", or a downloaded file that seems missing. Every fact below was proven live in the Aldar COPADO org (2026-11-17) through six failed production runs; trust it over intuition.
---

# Copado Functions

Platform reference for Copado Functions and the Quality Integration Framework (QIF). Working implementation: `scripts/run_agentforce_tests.sh` (the Agentforce quality gate, green in production); org components map: `copado/README.md`; full design doc: `docs/agentforce-copado-cicd.md`.

## Failure signatures (check here first)

| Symptom | Cause | Fix |
|---|---|---|
| JE Error: `Invalid template name X, it must be a valid Template Api Name` | JobTemplate ApiName is auto-normalized on insert: spaces → underscores (`"Run My Tests"` v1 → `Run_My_Tests_1`), even when you set ApiName explicitly | Point the Test Tool / caller at the REAL ApiName — query `copado__JobTemplate__c.copado__ApiName__c`, never assume |
| JE `Canceled`, Result: "timed out after 5 minutes" | `copado__Function__c.copado__Timeout__c` is in MINUTES and null means a ~5-minute default | Set Timeout = 30 on the Function record |
| `AuthCodeUsernameRetrievalError` + HTML `405 Only POST allowed` on a mangled URL | `{$Source.Credential.Endpoint}` resolves to the full SOAP endpoint (`https://host/services/Soap/u/...`), not an instance URL | Extract the host first: `HOST=$(echo "$endpoint" | cut -d'/' -f3)` then `sf org login access-token --instance-url "https://$HOST"` |
| `copado-git-get` → `128: Repository not authenticated` | Missing the `provider` parameter — git_json alone is not enough | Pass BOTH `git_json={$Context.Repository.Credential}` AND `provider={$Context.Git_Provider__c}` |
| Downloaded file "missing" after `copado --downloadfiles` | It downloaded fine — the file has NO extension (e.g. `Copado Commit changes`, not `...json`) | Find it with `ls -t | grep -i 'commit changes'`, never `*.json`; always `ls -la` after download when debugging |
| `npm install -g` fails or hangs in a function | Global installs hit permission issues in function containers | Install locally: `cd /tmp && npm init -y && npm install <pkg>`, add `/tmp/node_modules/.bin` to PATH — or use an image that ships the tool |
| Record insert fails `INVALID_FIELD_FOR_INSERT_UPDATE` on QGR Condition Tool/Status/Actions/ExecutionSequence or QGR ActionsList | Those fields are system-maintained mirrors | Omit them; set them only on the parent Quality Gate Rule |
| Gate's test run trivially passes with "no changes detected" | Manual Test-record "Run" produces a bare JE context (`testIds` only) | Only commit-triggered runs carry the full context; test via a real commit |

## Function record anatomy (`copado__Function__c`)

- `copado__API_Name__c` — referenced by Job Step ConfigJson `functionName`
- `copado__Script__c` — the bash script (PATCH this field to update logic)
- `copado__Image_Name__c` — **use `copado-multicloud-dx:v6`** for anything Salesforce: sf CLI 2.152.14, Node 22.20, `@salesforce/plugin-agent` 2.2.2 bundled. `copado-function-core:v1` is only the communication layer (NO sf CLI, Node too old to install current CLI). Always pin an explicit tag.
- `copado__Worker_Size__c` — S/M/L; M for CLI workloads
- `copado__Timeout__c` — MINUTES; null = ~5-minute kill. Set explicitly.
- `copado__Parameters__c` — JSON array `[{"name":..., "defaultValue":..., "required":...}]`; defaultValue may be a dynamic expression

Job Step wiring (`copado__JobStep__c`, type Function): `copado__ConfigJson__c` = `{"functionName": "<API_Name>", "parameters": [{"name":..., "value":...}]}`. Parameters become env vars in the script.

## The copado CLI inside functions (complete surface — nothing else exists)

```
copado -p "msg"                     # progress (REQUIRED at least once)
copado -e "error message"           # set error on the Result
copado -r '{"result":"..."}'        # structured result data
copado -u file [-n name] [-i id]    # upload/attach file to the Result
copado --downloadfiles <ContentVersionId>   # download a file to cwd
```

`copado --downloadfiles` is THE documented way to fetch the commit manifest ("file with selected metadata to commit"). There is no `copado -d`. Never silence its stderr — that cost a full debug cycle.

`copado-git-get [-d DIR] [--depth N] [-c] BRANCH` — clone/fetch/checkout. Requires function parameters `git_json={$Context.Repository.Credential}` **and** `provider={$Context.Git_Provider__c}`. Call once per branch; same directory accumulates.

## Dynamic expressions that work (proven)

| Expression | Resolves to |
|---|---|
| `{$Source.Credential.SessionId}` / `{$Source.Credential.Endpoint}` | User story's source org session / SOAP endpoint (extract host before sf login) |
| `{$Context.JobExecution__r.DataJson.<key>}` | Any key in the JE's DataJson (see contract below) |
| `{$Pipeline.Property.<name>}` | System Property on the pipeline |
| `{$Context.Repository.Credential}` | git_json payload for copado-git-get |
| `{$Context.Git_Provider__c}` | Git provider name (required partner of git_json) |
| `{$Context.Apex.<ClassName>}` | Return of a local Apex class implementing `copado.ParameterExpressionCallable` — `global String execute(Id contextId)`, contextId = **Job Step Id**; needs a no-arg constructor. Example (unused but complete): `copado/apex-expression-unused/` |

**QIF DataJson contract** (commit-triggered test runs get full enrichment): `userStoryId`, `userStoryName`, `userStoryCommitId`, `featureBranchName`, `baseBranch`, `environmentId`, `qualityCheck`, `testIds`, `resultIds`, `fileWithSelectedChanges` (ContentVersion id of the commit manifest). The manifest file: named `Copado Commit changes` (no extension), JSON array of `{t: Type, n: Name, a: Action}` — names arrive **version-suffixed** from published orgs (`Copado_Expert_1`); strip `_<digits>$` before using.

## Bridging to the sf CLI

```bash
HOST=$(echo "$sourceEndpoint" | cut -d'/' -f3)
export SF_ACCESS_TOKEN="$sourceSessionId"
sf org login access-token --instance-url "https://$HOST" --alias source --no-prompt >/dev/null
# then: sf <anything> -o source
```

No JWT, no secrets — Copado's own credential rides along. `sf agent` subcommands JIT-install plugin-agent if absent (dx:v6 already bundles it).

## QIF custom test tool (the 5 pieces)

1. **Job Template** (Custom) + Function step — note the ApiName normalization gotcha.
2. **Function** — see anatomy above.
3. **Test Tool custom metadata** (`copado__TestTool__mdt`): label must equal the Extension Configuration's `copado__ExtensionTool__c`; `copado__JobTemplate__c` = the template's real ApiName; `copado__Applicable_Metadata_Types__c` scopes it; mirror ApexTests' Run-On flags. Deployed as CustomMetadata.
4. **Tool picklist value**: `copado__Quality_Gate_Rule__c.copado__Tool__c` is backed by the subscriber-extendable global value set **`copado__Test_Tool`** — retrieve, add value, deploy (or Setup UI).
5. **Quality Gate Rule + Condition**: rule carries Tool/Type/Actions ("Commit")/Execution_sequence ("After")/`copado__Is_Updated_Data_Model__c=true`; condition carries Platform ("SFDX"), Pipeline, Environment or Stage, Extension_Configuration, Tests_From ("User Story"), Filter_Criteria grammar: `{$Changes.Type.equals("AiAuthoringBundle")} || ...` (one value per clause). Condition's Tool/Status/Actions/ExecutionSequence are system-maintained — never insert them.

Testing Center prerequisite: the target agent must be **published** (`sf agent publish authoring-bundle --api-name X`) or suite creation fails with "BotVersion not found". Runtime topic names drift (`topic_selector`) — avoid `expectedTopic` assertions.

## Debugging playbook

1. JE record: `copado__Status__c`, `copado__ErrorMessage__c`, `copado__Template__r.copado__ApiName__c`, `copado__DataJson__c` (what context arrived?)
2. Result record: `copado__Result__c` via `copado__JobStep__r.copado__JobExecution__c`, fields Status / Error_Message / Progress_Status
3. Function log: the Copado UI Result page, or ContentDocumentLink on the Result → latest ContentVersion → `/VersionData` (note: a timeout kill may leave no log)
4. Poller utility: `bash copado/tools/watch_je.sh` (edit JE_ID inside)
5. In scripts: never `2>/dev/null` a copado CLI call; `ls -la` after any download; echo parameter presence (`${param:+present}`) — never the values of credentials.

Test JEs are parented to the Test record (not the commit), so they never appear in the commit page's job-execution list; results live on the user story's Tests related list.
