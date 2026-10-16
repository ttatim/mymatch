<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit("Execução permitida somente em CLI.\n");
}

require __DIR__ . '/../app/bootstrap.php';

$name = $argv[1] ?? '';
if (!is_string($name)) exit("Uso: php bin/store-secret.php <nome-do-segredo>\n");
fwrite(STDERR, "Informe o valor do segredo (não será exibido): ");
$value = rtrim(stream_get_contents(STDIN), "\r\n");

try {
    store_vault_secret($name, $value);
    fwrite(STDOUT, "Segredo armazenado de forma cifrada.\n");
} catch (Throwable) {
    fwrite(STDERR, "Não foi possível armazenar o segredo.\n");
    exit(1);
}
