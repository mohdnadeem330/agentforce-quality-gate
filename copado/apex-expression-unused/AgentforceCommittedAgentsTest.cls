@IsTest
private class AgentforceCommittedAgentsTest {
    @IsTest
    static void userStoryIdParsing() {
        System.assertEquals(null, AgentforceCommittedAgents.userStoryIdFrom(null), 'blank json');
        System.assertEquals(null, AgentforceCommittedAgents.userStoryIdFrom('not json'), 'invalid json');
        System.assertEquals(null, AgentforceCommittedAgents.userStoryIdFrom('[1,2]'), 'non-object json');
        System.assertEquals('a1v000000000001', AgentforceCommittedAgents.userStoryIdFrom('{"userStoryId":"a1v000000000001"}'), 'happy path');
        System.assertEquals(null, AgentforceCommittedAgents.userStoryIdFrom('{"other":"x"}'), 'missing key');
    }

    @IsTest
    static void normalization() {
        System.assertEquals('Copado_Expert', AgentforceCommittedAgents.normalized('Copado_Expert_1'), 'strips version suffix');
        System.assertEquals('Copado_Expert', AgentforceCommittedAgents.normalized('Copado_Expert'), 'no suffix unchanged');
        System.assertEquals(null, AgentforceCommittedAgents.normalized(''), 'blank');
    }

    @IsTest
    static void agentsForStory() {
        copado__User_Story__c story = new copado__User_Story__c();
        insert story;

        insert new List<copado__User_Story_Metadata__c>{
            new copado__User_Story_Metadata__c(
                Name = 'Add AiAuthoringBundle.Copado_Expert_1',
                copado__User_Story__c = story.Id,
                copado__Type__c = 'AiAuthoringBundle',
                copado__Metadata_API_Name__c = 'Copado_Expert_1',
                copado__Unique_ID__c = story.Id + ';;AiAuthoringBundle;Copado_Expert_1'
            ),
            new copado__User_Story_Metadata__c(
                Name = 'Add AiAuthoringBundle.Copado_Expert_2',
                copado__User_Story__c = story.Id,
                copado__Type__c = 'AiAuthoringBundle',
                copado__Metadata_API_Name__c = 'Copado_Expert_2',
                copado__Unique_ID__c = story.Id + ';;AiAuthoringBundle;Copado_Expert_2'
            ),
            new copado__User_Story_Metadata__c(
                Name = 'Add ApexClass.SomeClass',
                copado__User_Story__c = story.Id,
                copado__Type__c = 'ApexClass',
                copado__Metadata_API_Name__c = 'SomeClass',
                copado__Unique_ID__c = story.Id + ';;ApexClass;SomeClass'
            )
        };

        Test.startTest();
        String agents = AgentforceCommittedAgents.agentsFor(story.Id);
        Test.stopTest();

        System.assertEquals('Copado_Expert', agents, 'versioned bundles collapse to one base agent name; non-agent types excluded');
        System.assertEquals('', AgentforceCommittedAgents.agentsFor(null), 'null story id');
    }

    @IsTest
    static void executeWithNoStep() {
        System.assertEquals('', new AgentforceCommittedAgents().execute(null), 'no job step resolves to empty');
    }
}
