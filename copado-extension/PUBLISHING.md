# Packaging & publishing to Copado DevOps Exchange

## What the package contains (`copado-extension/`)

Mirrors the anatomy of Copado's own `copado_labs` sfdx-scanner extension:

| Component | Purpose |
|---|---|
| `customMetadata/copado__TestTool.AgentTest.md-meta.xml` | Registers **AgentTest** as a quality tool: test type, applicable metadata (`AiAuthoringBundle`), run-on-commit flags, job template binding (`Run_Agentforce_Tests_1`) |
| `staticresources/AgentforceTestingGate.json` | **RecordSetBundles seed** — the Extension Configuration, Job Template, Job Step and Function (full script inline) that Copado's Quality Tools framework materializes in the subscriber org when the tool is configured |

Generated from the live, production-proven records by `copado/tools/build_extension_seed.py` (rerun it after any function/step change, then bump the package version).

Not packageable — subscriber post-install steps (documented for the listing):
1. Add the **`AgentTest`** value to the `copado__Test_Tool` global value set (Setup → Picklist Value Sets) — subscriber customizations of managed value sets can't ship in a package.
2. Create the Quality Gate Rule (After Commit, filter `{$Changes.Type.equals("AiAuthoringBundle")}`, scope to pipeline/environments) — org-specific by design.
3. Per agent: deploy a Testing Center suite named `<AgentApiName>_Suite` to the dev sandbox (requires a published agent + Testing Center enabled).

## Creating the unlocked package (one-time + per version)

Prereq: a **Dev Hub** org (`sf org login web --set-default-dev-hub --alias DevHub`; enable Setup → Dev Hub first). The Dev Hub *owns* the package — for personal distribution use a personal Developer Edition org, not an employer org.

```bash
# one-time: create the package (aliases + dependencies already in sfdx-project.json)
sf package create --name "Agentforce Testing Gate" --package-type Unlocked \
  --path copado-extension --target-dev-hub DevHub

# per release: create a version (skip-validation is fine while iterating; validate for release)
sf package version create --package "Agentforce Testing Gate" \
  --installation-key-bypass --wait 30 --target-dev-hub DevHub

# promote to released when ready for distribution
sf package version promote --package "Agentforce Testing Gate@1.0.0-1" --target-dev-hub DevHub

# test install (any org with Copado Deployer v24+ and Quality Tools v3+)
sf package install --package "Agentforce Testing Gate@1.0.0-1" -o <org> --wait 20
```

Note: `sf package version create` must validate the Copado dependencies — the Dev Hub needs access to those package versions (they are released 1GP versions, resolvable by 04t id; the aliases pin the versions proven in production).

## Publishing on DevOps Exchange

The Exchange is a partner marketplace — publishing is a business process, not a CLI step:

1. **Partnership agreement** — both for-profit and not-for-profit organizations can publish (free and/or paid listings), but a partnership agreement with Copado is required first. Start at the [DevOps Exchange](https://success.copado.com/s/exchange) / [integrations page](https://www.copado.com/integrations).
2. **Submission** — follow Copado's [Submit Instructions](https://success.copado.com/s/submit-instructions) (listing form: name, description, install link, documentation, support contact).
3. **Listing assets you already have**: the [design doc](../docs/agentforce-copado-cicd.md) with architecture/sequence/flow diagrams, the [repo README](../README.md) as the product page draft, install prerequisites (Deployer v24+, Quality Tools v3+, CSFP v6+), and the post-install steps above.
4. Expect a review cycle with the Copado partner team (they verify install + security posture; the gate's zero-new-secrets auth story — reusing Copado's own credentials — is a selling point).
