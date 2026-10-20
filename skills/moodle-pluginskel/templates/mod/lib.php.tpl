<?php
{{header}}

/**
 * Returns whether the module supports a feature.
 *
 * @param string $feature FEATURE_xx constant for the requested feature.
 * @return bool|string|null True if supported, a string for some features, null if unknown.
 */
function {{pluginname}}_supports($feature) {
    switch ($feature) {
        case FEATURE_MOD_INTRO:
        case FEATURE_SHOW_DESCRIPTION:
            return true;
        case FEATURE_BACKUP_MOODLE2:
            return false;
        case FEATURE_MOD_PURPOSE:
            return MOD_PURPOSE_OTHER;
        default:
            return null;
    }
}

/**
 * Saves a new instance of the module into the database.
 *
 * @param stdClass $data Form data submitted by mod_form.php.
 * @param {{component}}_mod_form|null $mform The form instance.
 * @return int The id of the new instance.
 */
function {{pluginname}}_add_instance(stdClass $data, ?{{component}}_mod_form $mform = null): int {
    global $DB;

    $data->timemodified = time();
    return $DB->insert_record('{{pluginname}}', $data);
}

/**
 * Updates an existing instance of the module in the database.
 *
 * @param stdClass $data Form data submitted by mod_form.php.
 * @param {{component}}_mod_form|null $mform The form instance.
 * @return bool
 */
function {{pluginname}}_update_instance(stdClass $data, ?{{component}}_mod_form $mform = null): bool {
    global $DB;

    $data->timemodified = time();
    $data->id = $data->instance;
    return $DB->update_record('{{pluginname}}', $data);
}

/**
 * Removes an instance of the module from the database.
 *
 * @param int $id Id of the module instance.
 * @return bool
 */
function {{pluginname}}_delete_instance(int $id): bool {
    global $DB;

    if (!$DB->record_exists('{{pluginname}}', ['id' => $id])) {
        return false;
    }
    $DB->delete_records('{{pluginname}}', ['id' => $id]);
    return true;
}
