@SuppressWarnings('PMD.AvoidGlobalModifier')
global with sharing class AgentforceCommittedAgents implements copado.ParameterExpressionCallable {
    // Invoked by the quality-gate job step as {$Context.Apex.AgentforceCommittedAgents}.
    // contextId is the Job Step Id. Returns a comma-separated list of Agentforce agent
    // names (AiAuthoringBundle) committed on the user story behind this test run,
    // with the org's version suffix (_1, _2 ...) stripped so <Agent>_Suite resolves.
    global String execute(Id contextId) {
        List<copado__JobStep__c> steps = [
            SELECT copado__JobExecution__r.copado__DataJson__c
            FROM copado__JobStep__c
            WHERE Id = :contextId
            LIMIT 1
        ];
        if (steps.isEmpty() || steps[0].copado__JobExecution__r == null) {
            return '';
        }
        return agentsFor(userStoryIdFrom(steps[0].copado__JobExecution__r.copado__DataJson__c));
    }

    @TestVisible
    private static String userStoryIdFrom(String dataJson) {
        if (String.isBlank(dataJson)) {
            return null;
        }
        try {
            Object parsed = JSON.deserializeUntyped(dataJson);
            if (!(parsed instanceof Map<String, Object>)) {
                return null;
            }
            Object usId = ((Map<String, Object>) parsed).get('userStoryId');
            return usId == null ? null : String.valueOf(usId);
        } catch (System.JSONException e) {
            return null;
        }
    }

    @TestVisible
    private static String agentsFor(String userStoryId) {
        if (String.isBlank(userStoryId)) {
            return '';
        }
        Set<String> names = new Set<String>();
        for (copado__User_Story_Metadata__c m : [
            SELECT copado__Metadata_API_Name__c
            FROM copado__User_Story_Metadata__c
            WHERE copado__User_Story__c = :userStoryId
            AND copado__Type__c = 'AiAuthoringBundle'
        ]) {
            String name = normalized(m.copado__Metadata_API_Name__c);
            if (String.isNotBlank(name)) {
                names.add(name);
            }
        }
        return String.join(new List<String>(names), ',');
    }

    @TestVisible
    private static String normalized(String bundleName) {
        if (String.isBlank(bundleName)) {
            return null;
        }
        // Published orgs expose versioned bundles (Copado_Expert_1); the suite
        // convention keys on the base agent name.
        String base = bundleName.replaceAll('_\\d+$', '');
        return String.isBlank(base) ? bundleName : base;
    }
}
