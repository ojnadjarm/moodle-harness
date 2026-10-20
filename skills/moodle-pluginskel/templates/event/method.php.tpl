{{#emit}}
    /**
     * Triggers {{name}} when {{observed}} happens.
     *
     * @param \{{observed}} $event
     */
    public static function {{methodname}}(\{{observed}} $event): void {
        event\{{name}}::create([
            'context' => $event->get_context(),
            'userid' => $event->userid,
{{#objecttable}}
            'objectid' => $event->objectid,
{{/objecttable}}
        ])->trigger();
    }
{{/emit}}
{{#handler}}
    /**
     * Handles {{observed}}.
     *
     * @param \{{observed}} $event
     */
    public static function {{methodname}}(\{{observed}} $event): void {
{{#table}}
        global $DB;

        $DB->delete_records('{{table}}', ['userid' => $event->relateduserid]);
{{/table}}
{{#notable}}
        $objectid = $event->objectid;
        $relateduserid = $event->relateduserid;
        $contextid = $event->contextid;
        debugging("TODO: handle {$event->eventname} (objectid {$objectid}, relateduserid {$relateduserid}, " .
            "contextid {$contextid})", DEBUG_DEVELOPER);
{{/notable}}
    }
{{/handler}}
