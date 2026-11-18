#!/bin/bash
set -e

# Copado Function: Agentforce agent deployment orchestration (API v68.0+ agents only)
#
# Post-deployment step for Copado promotions of AiAuthoringBundle agents:
# publish/activate the deployed draft, then run the Testing Center suite as a
# quality gate. v68 bundle deploys only touch the draft, so no pre-deployment
# deactivation is ever needed. Legacy Bot/GenAiPlanner support (pre-phase
# deactivation + Connect API re-activation) was removed 2026-11-18 — it lives
# in git history if ever needed again.
#
# Parameters (Copado Function parameters -> env vars, same convention as flow_activation.sh):
#   agent_api_name        required  BotDefinition DeveloperName (e.g. Copado_Expert)
#   agent_bundle_name     optional  AiAuthoringBundle name (default: agent_api_name; commit
#                                   manifests can deliver version-suffixed names, e.g. Copado_Expert_1)
#   publish_mode          optional  publish | none (default publish)
#                                   publish = sf agent publish authoring-bundle (creates AND
#                                             activates a new version from the deployed draft)
#                                   none    = skip activation (e.g. validation-only step)
#   test_suite_api_name   optional  AiEvaluationDefinition API name to run. The suite
#                                   arrives as metadata promoted alongside the agent (metadata-first
#                                   pattern); authoring suites from YAML specs belongs to the dev
#                                   loop, not deployment steps.
#   test_pass_threshold   optional  minimum % of test cases passing output_validation (default 80)
#   test_wait_minutes     optional  max minutes to wait for the test run (default 15)
#   sessionID, endpointID           standard Copado org-credential parameters

# ---------- validation ----------
if [ -z "$agent_api_name" ]; then
    echo "Error: agent_api_name parameter is required"
    exit 1
fi

agent_bundle_name="${agent_bundle_name:-$agent_api_name}"
publish_mode="${publish_mode:-publish}"
test_pass_threshold="${test_pass_threshold:-80}"
test_wait_minutes="${test_wait_minutes:-15}"

# Extract instance URL from endpoint (same pattern as flow_activation.sh)
InstanceUrl=$(echo "$endpointID" | cut -d'/' -f3)
InstanceUrl="https://$InstanceUrl"

ensure_sf_cli() {
    # Image copado-multicloud-dx:v6 ships sf CLI 2.152.14 (Node 22) with
    # @salesforce/plugin-agent bundled — no install step. Older images (e.g.
    # copado-function-core:v1, Node 18) can't run current CLI/plugin-agent.
    if ! command -v sf >/dev/null 2>&1; then
        echo "Error: sf CLI not found. Register this function with image copado-multicloud-dx:v6."
        exit 1
    fi
    copado --progress "Using $(sf version 2>/dev/null || echo 'sf CLI')"
    # Authenticate sf CLI with the Copado session (no password/JWT needed)
    export SF_ACCESS_TOKEN="$sessionID"
    sf org login access-token --instance-url "$InstanceUrl" --alias target --no-prompt >/dev/null
}

ensure_sf_cli

# Step 1: publish / activate
case "$publish_mode" in
publish)
    copado --progress "Publishing authoring bundle $agent_bundle_name"
    # Creates a new version from the deployed draft and activates it (API 68.0 model)
    sf agent publish authoring-bundle --api-name "$agent_bundle_name" -o target --json \
        | tee /tmp/publish.json
    if ! jq -e '.status == 0' /tmp/publish.json >/dev/null; then
        copado --progress "Agent publish failed"
        exit 1
    fi
    copado --progress "Agent published and active"
    ;;
none)
    copado --progress "Skipping publish/activate (publish_mode=none)"
    ;;
*)
    echo "Error: unknown publish_mode '$publish_mode' (expected publish|none)"
    exit 1
    ;;
esac

# Step 2: Testing Center quality gate
if [ -z "$test_suite_api_name" ]; then
    copado --progress "No test suite configured - done"
    echo "No test_suite_api_name given; skipping Testing Center gate"
    exit 0
fi

copado --progress "Running Testing Center suite $test_suite_api_name"
sf agent test run --api-name "$test_suite_api_name" \
    --wait "$test_wait_minutes" --result-format json -o target --json \
    | tee /tmp/test_run.json || true

JOB_ID=$(jq -r '.result.runId // empty' /tmp/test_run.json)
if [ -z "$JOB_ID" ]; then
    copado --progress "Test run did not start"
    echo "Error: could not start test run: $(cat /tmp/test_run.json)"
    exit 1
fi

sf agent test results --job-id "$JOB_ID" --result-format json -o target --json \
    | tee /tmp/test_results.json >/dev/null

# Gate on output_validation (LLM-as-judge; always present because every case sets
# expectedOutcome). topic_assertion false-negatives on guardrail cases are ignored.
read -r PASSED TOTAL RATE <<< "$(python3 -c "
import json
d = json.load(open('/tmp/test_results.json'))
cases = d.get('result', {}).get('testCases', [])
total = len(cases)
passed = 0
for tc in cases:
    results = {r['name']: r['result'] for r in tc.get('testResults', [])}
    if results.get('output_validation') == 'PASS':
        passed += 1
rate = int(passed * 100 / total) if total else 0
print(passed, total, rate)
")"

echo "Testing Center gate: ${PASSED}/${TOTAL} cases passed output_validation (${RATE}% vs threshold ${test_pass_threshold}%)"

if [ "$TOTAL" -eq 0 ]; then
    copado --progress "Gate failed: no test cases"
    echo "Error: suite '$test_suite_api_name' returned zero test cases"
    exit 1
fi

if [ "$RATE" -lt "$test_pass_threshold" ]; then
    copado --progress "Quality gate FAILED: ${RATE}% < ${test_pass_threshold}%"
    python3 -c "
import json
d = json.load(open('/tmp/test_results.json'))
for tc in d['result']['testCases']:
    results = {r['name']: r['result'] for r in tc.get('testResults', [])}
    if results.get('output_validation') != 'PASS':
        print('FAILED:', tc['inputs']['utterance'][:80])
"
    exit 1
fi

copado --progress "Quality gate passed: ${RATE}%"
echo "Agent '$agent_api_name' deployed, published, and gated successfully"
