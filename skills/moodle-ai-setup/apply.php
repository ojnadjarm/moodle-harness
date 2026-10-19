<?php
// Reconciles a Moodle site's AI config with a spec; runs inside the app container via `ai-setup`.
// Usage: php apply.php --mode=apply|check [--spec-b64=<base64 json>]; the API key comes from env AISETUP_APIKEY.

define('CLI_SCRIPT', true);
require('/var/www/html/config.php');
require_once($CFG->libdir . '/clilib.php');

[$opts] = cli_get_params(['mode' => 'check', 'spec-b64' => '']);
$apply = $opts['mode'] === 'apply';
$specfile = $CFG->dataroot . '/ai-setup.json';

if ($opts['spec-b64'] !== '') {
    $spec = json_decode(base64_decode($opts['spec-b64']), true, 512, JSON_THROW_ON_ERROR);
} else if (is_readable($specfile)) {
    $spec = json_decode(file_get_contents($specfile), true, 512, JSON_THROW_ON_ERROR);
} else {
    cli_error("no spec: run ai-setup with --provider first ({$specfile} missing)", 2);
}
$apikey = getenv('AISETUP_APIKEY') ?: null;

$changed = 0;
$drift = 0;

/** Prints one line and counts it: ok when $same, else set (apply) or drift (check). */
function report(bool $same, string $key, string $want, string $have = ''): void {
    global $apply, $changed, $drift;
    if ($same) {
        echo "ok    {$key} {$want}\n";
    } else if ($apply) {
        $changed++;
        echo "set   {$key} {$want}" . ($have !== '' ? " (was {$have})" : '') . "\n";
    } else {
        $drift++;
        echo "drift {$key} want {$want} have " . ($have !== '' ? $have : '-') . "\n";
    }
}

/** Provider instance named in the spec, with every action enabled and both hourly limits. */
function reconcile_provider(array $spec, ?string $apikey): void {
    global $apply;
    $manager = \core\di::get(\core_ai\manager::class);
    $classname = "\\aiprovider_{$spec['provider']}\\provider";
    if (!class_exists($classname)) {
        cli_error("provider aiprovider_{$spec['provider']} is not installed", 2);
    }
    $want = [
        'enableuserratelimit' => true,
        'userratelimit' => $spec['limit'],
        'enableglobalratelimit' => true,
        'globalratelimit' => $spec['sitelimit'],
    ];
    if ($spec['endpoint'] !== '') {
        $want['endpoint'] = $spec['endpoint'];
    }
    $records = $manager->get_provider_records(['provider' => ltrim($classname, '\\'), 'name' => $spec['name']]);
    $record = reset($records);
    $instances = $record ? $manager->get_provider_instances(['id' => $record->id]) : [];
    $provider = reset($instances) ?: null;

    $label = "provider {$spec['provider']} \"{$spec['name']}\"";
    report((bool)$provider, $label, 'exists', 'missing');
    if (!$provider && $apply) {
        $config = $want + ($apikey !== null ? ['apikey' => $apikey] : []);
        $provider = $manager->create_provider_instance($classname, $spec['name'], true, $config);
    }
    $config = $provider ? $provider->config : [];

    foreach ($want as $key => $value) {
        $have = $config[$key] ?? null;
        $same = is_bool($value) ? (bool)$have === $value : (string)$have === (string)$value;
        report($same, "provider.{$key}", var_export($value, true), $have === null ? '' : var_export($have, true));
        $config[$key] = $value;
    }
    if ($apikey !== null) {
        report(($provider?->config['apikey'] ?? null) === $apikey, 'provider.apikey', '(from file)', '(other)');
        $config['apikey'] = $apikey;
    }
    if (!$provider) {
        return;
    }
    $actionconfig = $provider->actionconfig;
    foreach ($classname::get_action_list() as $action) {
        $on = !empty($actionconfig[$action]['enabled']);
        report($on, 'provider.action.' . $action::get_basename(), 'enabled', 'disabled');
        $actionconfig[$action]['enabled'] = true;
    }
    if ($apply) {
        $provider = $manager->update_provider_instance($provider, $config, $actionconfig);
    }
    report((bool)$provider->enabled, 'provider.enabled', 'yes', 'no');
    if ($apply) {
        $manager->enable_provider_instance($provider);
    }
}

/** Every installed placement and each of its actions switched on. */
function reconcile_placements(): void {
    global $apply;
    foreach (core_plugin_manager::instance()->get_plugins_of_type('aiplacement') as $plugin) {
        $component = "aiplacement_{$plugin->name}";
        report((bool)$plugin->is_enabled(), "placement {$plugin->name}", 'enabled', 'disabled');
        if ($apply) {
            \core\plugininfo\aiplacement::enable_plugin($plugin->name, 1);
        }
        $actions = ("\\{$component}\\placement")::get_action_list();
        foreach ($actions as $action) {
            $basename = $action::get_basename();
            report(get_config($component, $basename) === '1', "placement.{$plugin->name}.{$basename}", 'enabled',
                get_config($component, $basename) === false ? 'unset' : get_config($component, $basename));
            if ($apply) {
                set_config($basename, 1, $component);
            }
        }
    }
}

/** Placement capabilities allowed for the listed roles only; any other role's system allow becomes prevent. */
function reconcile_capabilities(array $roles): void {
    global $DB, $apply;
    $syscontext = context_system::instance();
    $all = $DB->get_records_menu('role', null, 'sortorder', 'shortname, id');
    if ($missing = array_diff($roles, array_keys($all))) {
        cli_error('unknown role(s): ' . implode(', ', $missing), 2);
    }
    $caps = $DB->get_fieldset_select('capabilities', 'name', $DB->sql_like('component', ':c'), ['c' => 'aiplacement\_%']);
    sort($caps);
    foreach ($caps as $cap) {
        foreach ($all as $shortname => $roleid) {
            $have = (int)$DB->get_field('role_capabilities', 'permission',
                ['roleid' => $roleid, 'capability' => $cap, 'contextid' => $syscontext->id]);
            if (in_array($shortname, $roles)) {
                $want = CAP_ALLOW;
            } else if ($have === CAP_ALLOW) {
                $want = CAP_PREVENT;
            } else {
                continue;
            }
            $names = [CAP_ALLOW => 'allow', CAP_PREVENT => 'prevent', CAP_PROHIBIT => 'prohibit', CAP_INHERIT => 'notset'];
            report($have === $want, "cap {$cap} {$shortname}", $names[$want], $names[$have] ?? (string)$have);
            if ($apply && $have !== $want) {
                assign_capability($cap, $want, $roleid, $syscontext->id, true);
            }
        }
    }
}

/** The AI usage policy text as a local language override of core_ai/userpolicy. */
function reconcile_policy(string $policy): void {
    global $CFG, $apply;
    $dir = $CFG->langlocalroot . '/en_local';
    $file = $dir . '/ai.php';
    $string = [];
    if (is_readable($file)) {
        include($file);
    }
    $have = $string['userpolicy'] ?? '';
    $live = get_string_manager()->get_string('userpolicy', 'core_ai', null, 'en');
    report($have === $policy && $live === $policy, 'policy core_ai/userpolicy', sha1($policy) . " ({$file})",
        $have === '' ? 'core default' : sha1($have));
    if ($apply && ($have !== $policy || $live !== $policy)) {
        $string['userpolicy'] = $policy;
        check_dir_exists($dir);
        $php = "<?php\n// Local overrides of core_ai strings.\ndefined('MOODLE_INTERNAL') || die();\n\n";
        foreach ($string as $key => $value) {
            $php .= '$string[' . var_export($key, true) . '] = ' . var_export($value, true) . ";\n";
        }
        file_put_contents($file, $php);
        get_string_manager()->reset_caches(true);
    }
}

reconcile_provider($spec, $apikey);
reconcile_placements();
reconcile_capabilities($spec['roles']);
reconcile_policy($spec['policy']);

if ($apply) {
    file_put_contents($specfile, json_encode($spec, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");
    echo "changed: {$changed}\n";
    exit(0);
}
echo "drift: {$drift}\n";
exit($drift ? 1 : 0);
