<?php
declare(strict_types=1);

session_name('mymatch_session');
session_start([
    'cookie_httponly' => true,
    'cookie_samesite' => 'Lax',
    'cookie_secure' => !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off',
    'use_only_cookies' => true,
    'use_strict_mode' => true,
]);

require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/security.php';

header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('Referrer-Policy: strict-origin-when-cross-origin');
header('Permissions-Policy: camera=(), microphone=(), geolocation=()');
header("Content-Security-Policy: default-src 'self'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'; object-src 'none'; connect-src 'self'; img-src 'self' https: data:; font-src 'self' https://cdn.jsdelivr.net data:; style-src 'self' https://cdn.jsdelivr.net 'unsafe-inline'; script-src 'self' https://cdn.jsdelivr.net");
header('Cache-Control: no-store, max-age=0');

function e(?string $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function csrf_token(): string
{
    $_SESSION['csrf'] ??= bin2hex(random_bytes(32));
    return $_SESSION['csrf'];
}

function verify_csrf(): void
{
    $submitted = $_POST['csrf'] ?? '';
    if (!is_string($submitted) || !hash_equals($_SESSION['csrf'] ?? '', $submitted)) {
        http_response_code(419);
        exit('Sessão expirada. Atualize a página e tente novamente.');
    }
}

function clear_authenticated_session(): void
{
    $_SESSION = [];
    session_regenerate_id(true);
}

function current_user(): ?array
{
    static $user = false;
    if ($user !== false) return $user;
    if (empty($_SESSION['user_id'])) return $user = null;

    $statement = db()->prepare('SELECT id, email, status, birth_date, is_admin FROM users WHERE id = :id');
    $statement->execute(['id' => $_SESSION['user_id']]);
    return $user = $statement->fetch() ?: null;
}

function require_admin(): array
{
    $user = require_login();
    if (!$user['is_admin']) {
        http_response_code(403);
        exit('Acesso administrativo não autorizado.');
    }
    return $user;
}

function require_login(): array
{
    $user = current_user();
    if (!$user || $user['status'] !== 'active') {
        header('Location: index.php?page=login');
        exit;
    }
    return $user;
}

function current_plan(int $userId): string
{
    $statement = db()->prepare('SELECT plan FROM account_plans WHERE user_id=:id');
    $statement->execute(['id' => $userId]);
    return $statement->fetchColumn() ?: 'relationship_free';
}

function require_content_access(int $userId): void
{
    if (!in_array(current_plan($userId), ['content_free', 'content_plus', 'creator'], true)) {
        flash('warning', 'Selecione um plano de conteúdo para acessar esta área.');
        redirect('billing');
    }
}

function require_relationship_plus(int $userId): void
{
    if (current_plan($userId) !== 'relationship_plus') {
        flash('warning', 'Matches e conversas exigem o plano Relacionamentos Plus.');
        redirect('billing');
    }
}

function flash(string $type, string $message): void
{
    $_SESSION['flash'][] = ['type' => $type, 'message' => $message];
}

function redirect(string $page): never
{
    header('Location: index.php?page=' . urlencode($page));
    exit;
}

function eligible_for_interaction(int $fromUserId, int $toUserId): bool
{
    $sql = "SELECT EXISTS (
        SELECT 1 FROM users a JOIN users b ON b.id = :to
        JOIN relationship_profiles ap ON ap.user_id = a.id
        JOIN relationship_profiles bp ON bp.user_id = b.id
        WHERE a.id = :from AND a.status = 'active' AND b.status = 'active'
          AND ap.is_active AND bp.is_active
          AND NOT EXISTS (SELECT 1 FROM blocks x WHERE (x.blocker_id = :from AND x.blocked_id = :to) OR (x.blocker_id = :to AND x.blocked_id = :from))
    )";
    $statement = db()->prepare($sql);
    $statement->execute(['from' => $fromUserId, 'to' => $toUserId]);
    return (bool) $statement->fetchColumn();
}
