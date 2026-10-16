<?php
declare(strict_types=1);
require __DIR__ . '/app/bootstrap.php';

$user = require_login();
$mediaId = (int) ($_GET['id'] ?? 0);
$statement = db()->prepare(
    'SELECT cm.* FROM content_media cm JOIN content_posts cp ON cp.id=cm.content_id
     WHERE cm.id=:media AND (cp.producer_id=:user OR (
       cp.status=\'published\' AND NOT cp.is_adult AND (
         EXISTS (SELECT 1 FROM content_accesses a WHERE a.content_id=cp.id AND a.viewer_id=:viewer AND a.is_valid)
         OR EXISTS (SELECT 1 FROM content_purchases buy WHERE buy.content_id=cp.id AND buy.buyer_id=:viewer AND buy.status=\'approved\')
       )
     ))'
);
$statement->execute(['media' => $mediaId, 'user' => $user['id'], 'viewer' => $user['id']]);
$media = $statement->fetch();
if (!$media) {
    http_response_code(403);
    exit('Mídia indisponível.');
}
$path = media_storage_path($media['storage_key']);
if (!$path || !is_file($path)) {
    http_response_code(404);
    exit('Arquivo não encontrado.');
}
header('Content-Type: ' . $media['mime_type']);
header('Content-Length: ' . filesize($path));
header('X-Content-Type-Options: nosniff');
header('Cache-Control: private, no-store, max-age=0');
header('Content-Disposition: inline; filename="' . rawurlencode($media['original_name']) . '"');
readfile($path);
