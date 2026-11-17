#!/bin/bash
# Poll JE-70555 until terminal, then print result + function log tail
JE_ID="a0sMz00000DoajxIAB"
for i in $(seq 1 40); do
    STATUS=$(sf data query -o COPADO --json -q "SELECT copado__Status__c FROM copado__JobExecution__c WHERE Id='$JE_ID'" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['records'][0]['copado__Status__c'])")
    echo "[poll $i] $STATUS"
    case "$STATUS" in Successful|Error|Cancelled) break;; esac
    sleep 20
done
echo "=== FINAL STATUS: $STATUS ==="
sf data query -o COPADO --json -q "SELECT Id, copado__Status__c, copado__Error_Message__c, copado__Progress_Status__c FROM copado__Result__c WHERE copado__JobStep__r.copado__JobExecution__c='$JE_ID' ORDER BY CreatedDate DESC LIMIT 1" 2>/dev/null | python3 -c "
import json,sys
recs=json.load(sys.stdin)['result']['records']
if recs:
    r=recs[0]
    print('RESULT:', r['Id'], '| status:', r.get('copado__Status__c'), '| progress:', r.get('copado__Progress_Status__c'))
    print('error:', (r.get('copado__Error_Message__c') or 'none')[:500])
    open('/tmp/qif-build/result_id.txt','w').write(r['Id'])
else:
    print('no result record found')"
RESULT_ID=$(cat /tmp/qif-build/result_id.txt 2>/dev/null)
if [ -n "$RESULT_ID" ]; then
    CV_ID=$(sf data query -o COPADO --json -q "SELECT ContentDocument.LatestPublishedVersionId FROM ContentDocumentLink WHERE LinkedEntityId='$RESULT_ID' ORDER BY ContentDocument.ContentModifiedDate DESC LIMIT 1" 2>/dev/null | python3 -c "
import json,sys
recs=json.load(sys.stdin)['result']['records']
print(recs[0]['ContentDocument']['LatestPublishedVersionId'] if recs else '')")
    if [ -n "$CV_ID" ]; then
        echo "=== FUNCTION LOG (tail) ==="
        sf api request rest "/services/data/v62.0/sobjects/ContentVersion/$CV_ID/VersionData" -o COPADO 2>/dev/null | tail -60
    fi
fi
