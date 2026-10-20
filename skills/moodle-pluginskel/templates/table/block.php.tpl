$table = new \{{component}}\table\{{name}}('{{uniqueid}}'{{pageargs}});
{{#dynamicsystem}}
$table->set_filterset(new \{{component}}\table\{{name}}_filterset());
{{/dynamicsystem}}
{{#dynamiccourse}}
$filterset = new \{{component}}\table\{{name}}_filterset();
$filterset->add_filter(new \core_table\local\filter\integer_filter('courseid', null, [(int) $course->id]));
$table->set_filterset($filterset);
{{/dynamiccourse}}
