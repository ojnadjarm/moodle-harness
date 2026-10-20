define('CLI_SCRIPT', true);

require((function (): string {
    $root = __DIR__;
    while (!file_exists($root . '/config.php') || !file_exists($root . '/lib/setup.php')) {
        if (dirname($root) === $root) {
            fwrite(STDERR, 'No Moodle config.php above ' . __DIR__ . PHP_EOL);
            exit(1);
        }
        $root = dirname($root);
    }
    return $root . '/config.php';
})());
