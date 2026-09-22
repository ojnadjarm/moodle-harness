<?php
{{header}}

/**
 * Executed on plugin upgrade.
 *
 * @param int $oldversion Version we are upgrading from.
 * @return bool
 */
function xmldb_{{component}}_upgrade(int $oldversion): bool {
    return true;
}
