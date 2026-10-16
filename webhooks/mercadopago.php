<?php
declare(strict_types=1);
require __DIR__ . '/../app/bootstrap.php';
require __DIR__ . '/../app/payments.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') { http_response_code(405); exit; }
$dataId = $_GET['data_id'] ?? $_GET['data.id'] ?? '';
$signature = $_SERVER['HTTP_X_SIGNATURE'] ?? '';
$requestId = $_SERVER['HTTP_X_REQUEST_ID'] ?? '';
if (!is_string($dataId) || !is_string($signature) || !is_string($requestId) || !mercadopago_verify_webhook($signature, $requestId, $dataId)) {
    http_response_code(401); exit;
}
try {
    $remote = mercadopago_fetch_subscription($dataId);
    db()->beginTransaction();
    $insert = db()->prepare("INSERT INTO webhook_events(provider,request_id,resource_id,received_at) VALUES ('mercadopago',:request,:resource,NOW()) ON CONFLICT (provider,request_id) DO NOTHING");
    $insert->execute(['request' => $requestId, 'resource' => $dataId]);
    if ($insert->rowCount() === 0) { db()->commit(); http_response_code(200); exit; }
    mercadopago_sync_subscription($dataId, $remote);
    db()->prepare("UPDATE webhook_events SET processed_at=NOW() WHERE provider='mercadopago' AND request_id=:request")->execute(['request' => $requestId]);
    db()->commit();
    http_response_code(200);
} catch (Throwable) {
    if (db()->inTransaction()) db()->rollBack();
    http_response_code(500);
}
