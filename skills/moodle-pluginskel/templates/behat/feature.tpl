@{{component}}
Feature: {{title}}
  In order to use {{name}}
  As a user
  I need to see it on its page

  Background:
{{background}}
{{#scenarios}}

  Scenario: {{scenario}}
{{#visit}}
    Given I log in as "{{user}}"
    And I visit "{{page}}"
{{/visit}}
{{#coursepage}}
    When I am on the "{{identifier}}" "{{pagetype}}" page logged in as "{{user}}"
{{/coursepage}}
{{#editing}}
    And I turn editing mode on
{{/editing}}
{{#see}}
    {{keyword}} I should see "{{text}}"{{where}}
{{/see}}
{{/scenarios}}
