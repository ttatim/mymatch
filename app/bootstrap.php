<?php
declare(strict_types=1);

session_name('mymatch_session');
session_start([
    'cookie_httponly' => true,
    'cookie_samesite' => 'Lax',
    'cookie_secure' => isset($_SERVER['HTTPS']),
]);

require_once __DIR__ . '/../config/database.php';

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
    if (!hash_equals($_SESSION['csrf'] ?? '', $_POST['csrf'] ?? '')) {
        http_response_code(419);
        exit('Sessão expirada. Atualize a página e tente novamente.');
    }
}

function current_user(): ?array
{
    static $user = false;
    if ($user !== false) return $user;
    if (empty($_SESSION['user_id'])) return $user = null;

    $statement = db()->prepare('SELECT id, email, status, birth_date FROM users WHERE id = :id');
    $statement->execute(['id' => $_SESSION['user_id']]);
    return $user = $statement->fetch() ?: null;
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
