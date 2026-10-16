<?php
declare(strict_types=1);

function db(): PDO
{
    static $connection = null;

    if ($connection instanceof PDO) {
        return $connection;
    }

    $environment = strtolower(getenv('APP_ENV') ?: 'development');
    $host = getenv('DB_HOST') ?: '127.0.0.1';
    $port = getenv('DB_PORT') ?: '5432';
    $name = getenv('DB_NAME') ?: 'mymatch';
    $user = getenv('DB_USER') ?: 'postgres';
    $password = getenv('DB_PASSWORD') ?: '';
    $sslMode = strtolower(getenv('DB_SSLMODE') ?: ($environment === 'production' ? 'require' : 'prefer'));
    $allowedSslModes = ['disable', 'allow', 'prefer', 'require', 'verify-ca', 'verify-full'];

    if (!in_array($sslMode, $allowedSslModes, true)) throw new RuntimeException('DB_SSLMODE inválido.');
    if ($environment === 'production' && ($password === '' || in_array($sslMode, ['disable', 'allow', 'prefer'], true))) {
        throw new RuntimeException('Produção exige senha de banco e DB_SSLMODE seguro.');
    }

    $dsn = sprintf('pgsql:host=%s;port=%s;dbname=%s;connect_timeout=5;sslmode=%s', $host, $port, $name, $sslMode);

    $connection = new PDO($dsn, $user, $password, [PDO::ATTR_EMULATE_PREPARES => false]);
    $connection->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $connection->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);

    return $connection;
}
