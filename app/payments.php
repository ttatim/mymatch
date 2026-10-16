<?php
declare(strict_types=1);

function mercadopago_request(string $method, string $path, ?array $payload = null): array
{
    $handle = curl_init('https://api.mercadopago.com' . $path);
    $headers = ['Authorization: Bearer ' . vault_secret('mercadopago.access_token'), 'Accept: application/json'];
    if ($payload !== null) $headers[] = 'Content-Type: application/json';
    curl_setopt_array($handle, [
        CURLOPT_CUSTOMREQUEST => $method, CURLOPT_HTTPHEADER => $headers, CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 10, CURLOPT_TIMEOUT => 20,
        CURLOPT_POSTFIELDS => $payload === null ? null : json_encode($payload, JSON_THROW_ON_ERROR),
    ]);
    $body = curl_exec($handle);
    $status = (int) curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
    curl_close($handle);
    if (!is_string($body) || $status < 200 || $status >= 300) throw new RuntimeException('Mercado Pago indisponível ou recusou a operação.');
    $decoded = json_decode($body, true, 512, JSON_THROW_ON_ERROR);
    if (!is_array($decoded)) throw new RuntimeException('Resposta inválida do Mercado Pago.');
    return $decoded;
}

function mercadopago_create_subscription(string $reference, string $email, string $planName, int $amountCents): array
{
    $baseUrl = rtrim((string) getenv('APP_BASE_URL'), '/');
    if (!str_starts_with($baseUrl, 'https://')) throw new RuntimeException('APP_BASE_URL com HTTPS é obrigatório para pagamentos.');
    return mercadopago_request('POST', '/preapproval', [
        'reason' => $planName,
        'external_reference' => $reference,
        'payer_email' => $email,
        'auto_recurring' => ['frequency' => 1, 'frequency_type' => 'months', 'transaction_amount' => $amountCents / 100, 'currency_id' => 'BRL'],
        'back_url' => $baseUrl . '/index.php?page=billing',
        'status' => 'pending',
    ]);
}

function mercadopago_verify_webhook(string $signature, string $requestId, string $dataId): bool
{
    if ($signature === '' || $requestId === '' || $dataId === '') return false;
    $parts = [];
    foreach (explode(',', $signature) as $part) {
        [$key, $value] = array_pad(explode('=', trim($part), 2), 2, '');
        $parts[strtolower($key)] = $value;
    }
    if (!ctype_digit($parts['ts'] ?? '') || !preg_match('/^[a-f0-9]{64}$/i', $parts['v1'] ?? '')) return false;
    if (abs(time() - (int) $parts['ts']) > 300) return false;
    $manifest = 'id:' . strtolower($dataId) . ';request-id:' . $requestId . ';ts:' . $parts['ts'] . ';';
    return hash_equals(strtolower($parts['v1']), hash_hmac('sha256', $manifest, vault_secret('mercadopago.webhook_secret')));
}

function mercadopago_fetch_subscription(string $providerSubscriptionId): array
{
    return mercadopago_request('GET', '/preapproval/' . rawurlencode($providerSubscriptionId));
}

function mercadopago_cancel_subscription(string $providerSubscriptionId): array
{
    return mercadopago_request('PUT', '/preapproval/' . rawurlencode($providerSubscriptionId), ['status' => 'cancelled']);
}

function mercadopago_sync_subscription(string $providerSubscriptionId, array $remote): void
{
    $reference = $remote['external_reference'] ?? '';
    $status = $remote['status'] ?? '';
    if (!is_string($reference) || !preg_match('/^[0-9a-f-]{36}$/', $reference) || !is_string($status)) throw new RuntimeException('Assinatura remota inválida.');
    $st = db()->prepare("SELECT pt.id AS transaction_id,pt.subscription_id,s.user_id,s.plan FROM payment_transactions pt JOIN subscriptions s ON s.id=pt.subscription_id WHERE pt.external_reference=:reference AND pt.provider='mercadopago' FOR UPDATE");
    $st->execute(['reference' => $reference]);
    $local = $st->fetch();
    if (!$local) throw new RuntimeException('Assinatura sem referência local.');

    $localStatus = match ($status) {
        'authorized' => 'active',
        'paused' => 'past_due',
        'cancelled' => 'cancelled',
        default => 'pending',
    };
    db()->prepare('UPDATE subscriptions SET provider_subscription_id=:provider,status=:status,started_at=CASE WHEN :status_active THEN COALESCE(started_at,NOW()) ELSE started_at END,cancelled_at=CASE WHEN :status_cancelled THEN NOW() ELSE cancelled_at END WHERE id=:id')
        ->execute(['provider' => $providerSubscriptionId, 'status' => $localStatus, 'status_active' => $localStatus === 'active', 'status_cancelled' => $localStatus === 'cancelled', 'id' => $local['subscription_id']]);
    db()->prepare('UPDATE payment_transactions SET status=:status,approved_at=CASE WHEN :approved THEN COALESCE(approved_at,NOW()) ELSE approved_at END,payload=:payload WHERE id=:id')
        ->execute(['status' => $localStatus === 'active' ? 'approved' : ($localStatus === 'cancelled' ? 'rejected' : 'pending'), 'approved' => $localStatus === 'active', 'payload' => json_encode(['subscription_status' => $status], JSON_THROW_ON_ERROR), 'id' => $local['transaction_id']]);
    if ($localStatus === 'active') db()->prepare('UPDATE account_plans SET plan=:plan,updated_at=NOW() WHERE user_id=:user')->execute(['plan' => $local['plan'], 'user' => $local['user_id']]);
    if ($localStatus === 'cancelled') db()->prepare("UPDATE account_plans SET plan=CASE WHEN plan='relationship_plus' THEN 'relationship_free' WHEN plan='content_plus' THEN 'content_free' ELSE plan END,updated_at=NOW() WHERE user_id=:user AND plan=:plan")->execute(['user' => $local['user_id'], 'plan' => $local['plan']]);
}

function crypto_address_is_valid(string $asset, string $address): bool
{
    return match ($asset) {
        'bitcoin' => (bool) preg_match('/^(bc1[ac-hj-np-z02-9]{11,71}|[13][a-km-zA-HJ-NP-Z1-9]{25,34})$/', $address),
        'ethereum' => (bool) preg_match('/^0x[a-fA-F0-9]{40}$/', $address),
        default => false,
    };
}

function crypto_hash_is_valid(string $asset, string $hash): bool
{
    return match ($asset) {
        'bitcoin' => (bool) preg_match('/^[a-fA-F0-9]{64}$/', $hash),
        'ethereum' => (bool) preg_match('/^0x[a-fA-F0-9]{64}$/', $hash),
        default => false,
    };
}
