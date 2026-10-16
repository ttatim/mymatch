<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') exit("Somente CLI.\n");
require __DIR__ . '/../app/bootstrap.php';

$errors = [];
$warnings = [];
$check = static function (bool $condition, string $message) use (&$errors): void {
    if (!$condition) $errors[] = $message;
};
$warn = static function (bool $condition, string $message) use (&$warnings): void {
    if (!$condition) $warnings[] = $message;
};

$check(app_is_production(), 'APP_ENV deve ser production.');
$baseUrl = rtrim((string) getenv('APP_BASE_URL'), '/');
$check(str_starts_with($baseUrl, 'https://'), 'APP_BASE_URL deve usar HTTPS.');
try { app_encryption_key(); } catch (Throwable) { $errors[] = 'APP_ENCRYPTION_KEY é inválida ou ausente.'; }
try {
    $directory = upload_directory();
    $appRoot = realpath(dirname(__DIR__));
    $check($appRoot === false || !str_starts_with(realpath($directory) . '/', $appRoot . '/'), 'UPLOAD_DIRECTORY não pode ficar dentro da aplicação.');
    $warn((fileperms($directory) & 0o007) === 0, 'UPLOAD_DIRECTORY permite acesso a outros usuários do sistema.');
} catch (Throwable) { $errors[] = 'UPLOAD_DIRECTORY não está pronto para escrita privada.'; }

try {
    db()->query('SELECT 1');
    $requiredTables = ['users','system_secrets','mfa_totp','content_safety_reviews','payment_transactions','webhook_events','wallets','wallet_ledger'];
    $st = db()->prepare("SELECT to_regclass('public.' || :table)");
    foreach ($requiredTables as $table) {
        $st->execute(['table' => $table]);
        $check((bool) $st->fetchColumn(), 'Tabela obrigatória ausente: ' . $table . '. Aplique as migrações.');
    }
    $check((int) db()->query('SELECT count(*) FROM wallets WHERE id=1 AND kind=\'platform\' AND user_id IS NULL')->fetchColumn() === 1, 'Carteira da plataforma id 1 não está íntegra.');
    $secretCheck = db()->prepare('SELECT EXISTS(SELECT 1 FROM system_secrets WHERE name=:name AND is_active)');
    foreach (['mercadopago.access_token','mercadopago.webhook_secret'] as $secret) {
        $secretCheck->execute(['name' => $secret]);
        $check((bool) $secretCheck->fetchColumn(), 'Segredo obrigatório ausente no cofre: ' . $secret . '.');
    }
    $secretCheck->execute(['name' => 'mistral.api_key']);
    $warn((bool) $secretCheck->fetchColumn(), 'mistral.api_key ausente: a fila automática de mídia será encaminhada para revisão humana.');
    $warn((int) db()->query("SELECT count(*) FROM users WHERE email LIKE '%@mymatch.local'")->fetchColumn() === 0, 'Há contas de demonstração no banco de produção.');
} catch (Throwable) {
    $errors[] = 'Não foi possível validar a conexão e o esquema do PostgreSQL.';
}

foreach ($warnings as $warning) fwrite(STDOUT, "AVISO: {$warning}\n");
foreach ($errors as $error) fwrite(STDERR, "ERRO: {$error}\n");
if ($errors) exit(1);
fwrite(STDOUT, "OK: prévia de produção aprovada" . ($warnings ? ' com avisos.' : '.') . "\n");
