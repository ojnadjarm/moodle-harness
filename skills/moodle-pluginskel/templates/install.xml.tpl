<?xml version="1.0" encoding="UTF-8" ?>
<XMLDB PATH="{{plugindir}}/db" VERSION="{{xmldbversion}}" COMMENT="XMLDB file for Moodle {{plugindir}}"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:noNamespaceSchemaLocation="{{xsdrel}}lib/xmldb/xmldb.xsd"
>
  <TABLES>
{{#tables}}
    <TABLE NAME="{{name}}" COMMENT="{{comment}}">
      <FIELDS>
{{#fields}}
        <FIELD NAME="{{name}}" {{attrs}}/>
{{/fields}}
      </FIELDS>
      <KEYS>
{{#keys}}
        <KEY NAME="{{name}}" TYPE="{{type}}" FIELDS="{{fields}}"{{ref}}/>
{{/keys}}
      </KEYS>
{{#has_indexes}}
      <INDEXES>
{{#indexes}}
        <INDEX NAME="{{name}}" UNIQUE="{{unique}}" FIELDS="{{fields}}"/>
{{/indexes}}
      </INDEXES>
{{/has_indexes}}
    </TABLE>
{{/tables}}
  </TABLES>
</XMLDB>
