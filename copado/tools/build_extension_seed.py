#!/usr/bin/env python3
"""Build the Copado extension seed static resource (RecordSetBundles format)
from the live records in the COPADO org.

The format mirrors the copado_labs sfdx-scanner extension: a JSON static
resource holding ExtensionConfiguration + JobTemplate + JobStep + Function
records that Copado's Quality Tools framework materializes in the subscriber
org when the extension's tool is configured.

Usage: python3 copado/tools/build_extension_seed.py [org-alias]
Writes: copado-extension/main/default/staticresources/AgentforceTestingGate.json
"""
import json
import subprocess
import sys

ORG = sys.argv[1] if len(sys.argv) > 1 else "COPADO"
OUT = "copado-extension/main/default/staticresources/AgentforceTestingGate.json"

IDS = {
    "copado__ExtensionConfiguration__c": "a0fMz00000HDcVVIA1",
    "copado__JobTemplate__c": "a0uMz00000SddEHIAZ",
    "copado__JobStep__c": "a0tMz000014nLEzIAM",
    "copado__Function__c": "a0lMz00000ef0jOIAQ",
}

FIELDS = {
    "copado__ExtensionConfiguration__c": [
        "Name", "copado__AcceptanceCriteria__c", "copado__Active__c",
        "copado__ExtensionApplication__c", "copado__ExtensionTool__c",
        "copado__Status__c", "copado__TestType__c",
    ],
    "copado__JobTemplate__c": [
        "Name", "copado__ApiName__c", "copado__Type__c", "copado__Version__c",
    ],
    "copado__JobStep__c": [
        "Name", "copado__ApiName__c", "copado__ConfigJson__c",
        "copado__CustomType__c", "copado__IsSkipped__c",
        "copado__JobTemplate__c", "copado__Order__c", "copado__Type__c",
    ],
    "copado__Function__c": [
        "Name", "copado__API_Name__c", "copado__Description__c",
        "copado__Image_Name__c", "copado__Options__c", "copado__Parameters__c",
        "copado__Script__c", "copado__Timeout__c", "copado__Type__c",
        "copado__Version__c", "copado__Worker_Size__c",
    ],
}


def fetch(sobject: str, rec_id: str) -> dict:
    soql = f"SELECT {', '.join(FIELDS[sobject])} FROM {sobject} WHERE Id = '{rec_id}'"
    out = subprocess.run(
        ["sf", "data", "query", "-q", soql, "-o", ORG, "--json"],
        capture_output=True, text=True, check=True,
    )
    rec = json.loads(out.stdout)["result"]["records"][0]
    rec.pop("attributes", None)
    record = {"attributes": {"type": sobject}, "Id": rec_id}
    record.update({k: v for k, v in rec.items() if v is not None})
    return record


def main() -> None:
    bundles = [
        {"ObjectType": sobject, "Records": [fetch(sobject, rec_id)]}
        for sobject, rec_id in IDS.items()
    ]
    seed = {"recordTypeMap": {}, "RecordSetBundles": bundles, "blobsByUID": {}}
    with open(OUT, "w") as fh:
        json.dump(seed, fh, indent=1)
    print(f"wrote {OUT}")
    for b in bundles:
        print(f"  {b['ObjectType']}: {b['Records'][0].get('Name')}")


if __name__ == "__main__":
    main()
