<?php
if (patch_point() === 'before-php-buildconf') {
    $php_version_short = getenv('SPC_PHP_VERSION_SHORT');
    $fadogen_var = "FADOGEN_PHP_{$php_version_short}_INI_SCAN_DIR";

    \SPC\store\FileSystem::replaceFileStr(
        SOURCE_PATH . '/php-src/main/php_ini.c',
        '"PHP_INI_SCAN_DIR"',
        '"' . $fadogen_var . '"'
    );
}