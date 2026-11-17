#!/bin/bash
set -e

# Copado Function: Agentforce Testing Center quality gate (QIF).
# Suite-agnostic: derives the committed agents from the user story's commit
# manifest and runs <AgentApiName>_Suite for each one. A committed agent with
# no deployed suite FAILS the gate (every agent must ship with its tests).
#
# Parameters (Job Step config / dynamic expressions):
#   sourceSessionId  {$Source.Credential.SessionId}
#   sourceEndpoint   {$Source.Credential.Endpoint}
#   changesFileId    {$Context.JobExecution__r.DataJson.fileWithSelectedChanges}
#   userStoryName    {$Context.JobExecution__r.DataJson.userStoryName}  (logging)
#   suiteNames       fallback suites when no commit manifest is present
#   passThreshold    min % of cases passing output_validation (default 80)
#   waitMinutes      max minutes per suite run (default 15)

passThreshold="${passThreshold:-80}"
waitMinutes="${waitMinutes:-15}"

if [ -z "$sourceSessionId" ] || [ -z "$sourceEndpoint" ]; then
    echo "Error: sourceSessionId and sourceEndpoint are required"
    exit 1
fi

copado --progress "Preparing Salesforce CLI"
if ! command -v sf >/dev/null 2>&1; then
    echo "ERROR: Salesforce CLI not found in this image. Use copado-multicloud-dx:v6"
    echo "(ships sf CLI with @salesforce/plugin-agent bundled). Core/v1 images lack it"
    echo "and current CLI requires Node >= 22, so installing at runtime is not supported."
    exit 1
fi
# Copado credential endpoints are SOAP URLs (https://host/services/Soap/u/...);
# sf needs the bare instance URL - extract the host (same pattern as flow_activation.sh)
SRC_HOST=$(echo "$sourceEndpoint" | cut -d'/' -f3)
export SF_ACCESS_TOKEN="$sourceSessionId"
sf org login access-token --instance-url "https://${SRC_HOST}" --alias source --no-prompt >/dev/null

# ---- Resolve suites from the committed agents (convention: <Agent>_Suite) ----
# Official pattern (docs: Example Function Commands - "Download the file with
# selected metadata to commit"): copado --downloadfiles <ContentVersionId>.
SUITES=""
if [ -n "$changesFileId" ]; then
    copado --progress "Downloading commit manifest"
    echo "Downloading file with Id: $changesFileId"
    copado --downloadfiles "$changesFileId" || echo "downloadfiles exited with $?"
    echo "--- workdir after download ---"
    ls -la
    # The file arrives WITHOUT a .json extension ("Copado Commit changes")
    CHANGES_FILE=$(ls -t 2>/dev/null | grep -i 'commit changes' | head -1)
    [ -z "$CHANGES_FILE" ] && CHANGES_FILE=$(ls -t *.json 2>/dev/null | head -1)
    if [ -n "$CHANGES_FILE" ]; then
        echo "Parsing manifest: $CHANGES_FILE"
        # Bundle names arrive version-suffixed from published orgs (Copado_Expert_1);
        # the suite convention keys on the base agent name.
        AGENTS=$(jq -r '.[] | select(.t == "AiAuthoringBundle") | .n' "$CHANGES_FILE" 2>/dev/null | sed -E 's/_[0-9]+$//' | sort -u)
        for A in $AGENTS; do SUITES="$SUITES ${A}_Suite"; done
        echo "Committed agents: $AGENTS"
    else
        echo "No manifest file found after download; will use fallback suites"
    fi
fi

if [ -z "$(echo "$SUITES" | tr -d ' ')" ]; then
    SUITES=$(echo "$suiteNames" | tr ',' ' ')
fi
if [ -z "$(echo "$SUITES" | tr -d ' ')" ]; then
    copado --progress "No agent changes detected - gate not applicable"
    echo "No committed agents and no fallback suites configured; passing trivially."
    exit 0
fi

OVERALL_RC=0
for SUITE in $SUITES; do
    copado --progress "Running suite $SUITE"
    sf agent test run --api-name "$SUITE" --wait "$waitMinutes" \
        --result-format json -o source --json > "run_${SUITE}.json" || true

    JOB_ID=$(jq -r '.result.runId // empty' "run_${SUITE}.json")
    if [ -z "$JOB_ID" ]; then
        MSG=$(jq -r '.message // "unknown error"' "run_${SUITE}.json")
        echo "GATE FAIL: suite $SUITE did not start: $MSG"
        echo "Policy: every committed agent needs a Testing Center suite named <AgentApiName>_Suite."
        OVERALL_RC=1
        continue
    fi

    sf agent test results --job-id "$JOB_ID" --result-format json -o source --json \
        > "results_${SUITE}.json"

    read -r PASSED TOTAL RATE <<< "$(python3 - "$SUITE" <<'PY'
import json, sys
d = json.load(open(f"results_{sys.argv[1]}.json"))
cases = d.get('result', {}).get('testCases', [])
total = len(cases)
passed = sum(1 for tc in cases
             if {r['name']: r['result'] for r in tc.get('testResults', [])}
             .get('output_validation') == 'PASS')
print(passed, total, int(passed * 100 / total) if total else 0)
PY
)"

    echo "Suite $SUITE: ${PASSED}/${TOTAL} passed output_validation (${RATE}% vs threshold ${passThreshold}%)"
    if [ "$TOTAL" -eq 0 ] || [ "$RATE" -lt "$passThreshold" ]; then
        copado --progress "Suite $SUITE FAILED (${RATE}%)"
        jq -r '.result.testCases[]
               | select(([.testResults[] | select(.name=="output_validation" and .result=="PASS")] | length) == 0)
               | "FAILED: " + (.inputs.utterance | .[0:80])' "results_${SUITE}.json" 2>/dev/null || true
        OVERALL_RC=1
    else
        copado --progress "Suite $SUITE passed (${RATE}%)"
    fi
done

if [ "$OVERALL_RC" -eq 0 ]; then
    copado --progress "Agentforce gate passed for ${userStoryName:-story}"
else
    copado --progress "Agentforce gate FAILED for ${userStoryName:-story}"
fi
exit $OVERALL_RC
