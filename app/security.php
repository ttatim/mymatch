<?php
declare(strict_types=1);

function app_encryption_key(): string
{
    $encoded = getenv('APP_ENCRYPTION_KEY') ?: '';
    $key = base64_decode($encoded, true);
    if ($key === false || strlen($key) !== SODIUM_CRYPTO_SECRETBOX_KEYBYTES) {
        throw new RuntimeException('A chave APP_ENCRYPTION_KEY deve conter 32 bytes codificados em Base64.');
    }
    return $key;
}

function encrypt_mfa_secret(string $secret): string
{
    $nonce = random_bytes(SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
    return base64_encode($nonce . sodium_crypto_secretbox($secret, $nonce, app_encryption_key()));
}

function decrypt_mfa_secret(string $ciphertext): string
{
    $payload = base64_decode($ciphertext, true);
    if ($payload === false || strlen($payload) <= SODIUM_CRYPTO_SECRETBOX_NONCEBYTES) {
        throw new RuntimeException('Segredo MFA inválido.');
    }
    $nonce = substr($payload, 0, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
    $secret = sodium_crypto_secretbox_open(substr($payload, SODIUM_CRYPTO_SECRETBOX_NONCEBYTES), $nonce, app_encryption_key());
    if ($secret === false) throw new RuntimeException('Não foi possível abrir o segredo MFA.');
    return $secret;
}

function validate_secret_name(string $name): string
{
    $name = strtolower(trim($name));
    if (!preg_match('/^[a-z0-9][a-z0-9_.-]{2,99}$/', $name)) throw new RuntimeException('Nome de segredo inválido.');
    return $name;
}

function vault_secret(string $name): string
{
    $name = validate_secret_name($name);
    $statement = db()->prepare('SELECT ciphertext FROM system_secrets WHERE name=:name AND is_active');
    $statement->execute(['name' => $name]);
    $ciphertext = $statement->fetchColumn();
    if (!is_string($ciphertext) || $ciphertext === '') throw new RuntimeException('Segredo operacional não configurado: ' . $name);
    return decrypt_mfa_secret($ciphertext);
}

function store_vault_secret(string $name, string $value): void
{
    $name = validate_secret_name($name);
    if ($value === '') throw new RuntimeException('O valor do segredo não pode ser vazio.');
    $ciphertext = encrypt_mfa_secret($value);
    $statement = db()->prepare("INSERT INTO system_secrets(name,ciphertext,version,is_active,updated_at)
        VALUES (:name,:ciphertext,1,true,NOW())
        ON CONFLICT (name) DO UPDATE SET ciphertext=EXCLUDED.ciphertext, version=system_secrets.version+1, is_active=true, updated_at=NOW()");
    $statement->execute(['name' => $name, 'ciphertext' => $ciphertext]);
    db()->prepare("INSERT INTO audit_logs(action,subject_type,metadata) VALUES ('system_secret_updated','system_secret',:metadata)")
        ->execute(['metadata' => json_encode(['name' => $name])]);
}

function base32_encode_secret(string $bytes): string
{
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    $bits = '';
    foreach (str_split($bytes) as $byte) $bits .= str_pad(decbin(ord($byte)), 8, '0', STR_PAD_LEFT);
    $result = '';
    foreach (str_split($bits, 5) as $chunk) {
        if (strlen($chunk) < 5) $chunk = str_pad($chunk, 5, '0', STR_PAD_RIGHT);
        $result .= $alphabet[bindec($chunk)];
    }
    return $result;
}

function base32_decode_secret(string $value): string
{
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    $value = strtoupper(preg_replace('/[^A-Z2-7]/', '', $value) ?? '');
    $bits = '';
    foreach (str_split($value) as $character) {
        $position = strpos($alphabet, $character);
        if ($position === false) throw new RuntimeException('Segredo TOTP inválido.');
        $bits .= str_pad(decbin($position), 5, '0', STR_PAD_LEFT);
    }
    $bytes = '';
    foreach (str_split($bits, 8) as $chunk) if (strlen($chunk) === 8) $bytes .= chr(bindec($chunk));
    return $bytes;
}

function totp_code(string $secret, ?int $timestamp = null): string
{
    $counter = intdiv($timestamp ?? time(), 30);
    $binaryCounter = pack('N2', 0, $counter);
    $hash = hash_hmac('sha1', $binaryCounter, base32_decode_secret($secret), true);
    $offset = ord($hash[19]) & 0x0f;
    $number = ((ord($hash[$offset]) & 0x7f) << 24) | (ord($hash[$offset + 1]) << 16) | (ord($hash[$offset + 2]) << 8) | ord($hash[$offset + 3]);
    return str_pad((string) ($number % 1000000), 6, '0', STR_PAD_LEFT);
}

function verify_totp(string $secret, string $code): bool
{
    if (!preg_match('/^\d{6}$/', $code)) return false;
    foreach ([-30, 0, 30] as $offset) if (hash_equals(totp_code($secret, time() + $offset), $code)) return true;
    return false;
}

function make_recovery_code(): string
{
    return strtoupper(substr(bin2hex(random_bytes(5)), 0, 5) . '-' . substr(bin2hex(random_bytes(5)), 0, 5));
}

function password_meets_policy(string $password): bool
{
    return strlen($password) >= 12 && preg_match('/[A-Za-z]/', $password) && preg_match('/\d/', $password);
}

function app_is_production(): bool
{
    return strtolower(getenv('APP_ENV') ?: 'development') === 'production';
}

function upload_directory(): string
{
    $configured = trim(getenv('UPLOAD_DIRECTORY') ?: '');
    if ($configured === '') {
        if (app_is_production()) throw new RuntimeException('UPLOAD_DIRECTORY é obrigatório em produção.');
        $configured = dirname(__DIR__) . '/storage/uploads';
    }
    if (!str_starts_with($configured, '/')) throw new RuntimeException('UPLOAD_DIRECTORY deve ser um caminho absoluto.');
    $appRoot = realpath(dirname(__DIR__));
    $directory = rtrim($configured, '/');
    if (app_is_production() && $appRoot && str_starts_with($directory . '/', $appRoot . '/')) {
        throw new RuntimeException('UPLOAD_DIRECTORY deve ficar fora da raiz da aplicação em produção.');
    }
    if (!is_dir($directory) && !mkdir($directory, 0750, true) && !is_dir($directory)) throw new RuntimeException('Diretório de mídia indisponível.');
    if (!is_writable($directory)) throw new RuntimeException('Diretório de mídia sem permissão de escrita.');
    return $directory;
}

function media_storage_path(string $storageKey): ?string
{
    if (!preg_match('/^[a-f0-9]{48}$/', $storageKey)) return null;
    return upload_directory() . '/' . $storageKey;
}

function client_ip(): string
{
    $ip = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    return filter_var($ip, FILTER_VALIDATE_IP) ? $ip : '0.0.0.0';
}

function throttle_subject(string $value): string
{
    return hash('sha256', strtolower(trim($value)) . '|' . client_ip());
}

function auth_throttle_allowed(string $scope, string $subject): bool
{
    $st = db()->prepare('SELECT locked_until FROM auth_throttles WHERE scope=:scope AND subject_hash=:subject');
    $st->execute(['scope' => $scope, 'subject' => $subject]);
    $lockedUntil = $st->fetchColumn();
    return !$lockedUntil || strtotime((string) $lockedUntil) <= time();
}

function auth_throttle_failure(string $scope, string $subject): void
{
    $sql = "INSERT INTO auth_throttles(scope,subject_hash,attempts,window_started_at,locked_until)
        VALUES (:scope,:subject,1,NOW(),NULL)
        ON CONFLICT (scope,subject_hash) DO UPDATE SET
          attempts = CASE WHEN auth_throttles.window_started_at < NOW() - INTERVAL '15 minutes' THEN 1 ELSE auth_throttles.attempts + 1 END,
          window_started_at = CASE WHEN auth_throttles.window_started_at < NOW() - INTERVAL '15 minutes' THEN NOW() ELSE auth_throttles.window_started_at END,
          locked_until = CASE WHEN (CASE WHEN auth_throttles.window_started_at < NOW() - INTERVAL '15 minutes' THEN 1 ELSE auth_throttles.attempts + 1 END) >= 5 THEN NOW() + INTERVAL '15 minutes' ELSE NULL END";
    db()->prepare($sql)->execute(['scope' => $scope, 'subject' => $subject]);
}

function auth_throttle_clear(string $scope, string $subject): void
{
    db()->prepare('DELETE FROM auth_throttles WHERE scope=:scope AND subject_hash=:subject')->execute(['scope' => $scope, 'subject' => $subject]);
}
