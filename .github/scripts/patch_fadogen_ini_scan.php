<?php
/**
 * Patch script pour static-php-cli
 * Remplace PHP_INI_SCAN_DIR par FADOGEN_PHP_XX_INI_SCAN_DIR selon la version PHP
 */

if (patch_point() === 'before-php-buildconf') {
    // Étape 1: Ajouter la fonction personnalisée au début du fichier php_ini.c
    $custom_function = '
#include "php_version.h"

/* Fonction personnalisée Fadogen pour chercher la variable INI spécifique à la version */
static char* getenv_fadogen_php_ini_scan_dir() {
    char var_name[64];
    sprintf(var_name, "FADOGEN_PHP_%d%d_INI_SCAN_DIR", PHP_MAJOR_VERSION, PHP_MINOR_VERSION);
    return getenv(var_name);
}
';

    // Ajouter la fonction après les includes
    \SPC\store\FileSystem::replaceFileStr(
        SOURCE_PATH . '/php-src/main/php_ini.c',
        '#include "php_ini.h"',
        '#include "php_ini.h"' . $custom_function
    );

    // Étape 2: Remplacer tous les appels à getenv("PHP_INI_SCAN_DIR")
    \SPC\store\FileSystem::replaceFileStr(
        SOURCE_PATH . '/php-src/main/php_ini.c',
        'getenv("PHP_INI_SCAN_DIR")',
        'getenv_fadogen_php_ini_scan_dir()'
    );
}
