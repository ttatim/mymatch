<?php
declare(strict_types=1);

require __DIR__ . '/config/database.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, max-age=0');
header('X-Content-Type-Options: nosniff');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
    http_response_code(405);
    header('Allow: GET');
    echo '{"status":"method_not_allowed"}';
    exit;
}

try {
    db()->query('SELECT 1');
    echo '{"status":"ok"}';
} catch (Throwable) {
    http_response_code(503);
    echo '{"status":"unavailable"}';
}
