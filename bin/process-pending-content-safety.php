<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') exit("Somente CLI.\n");
require __DIR__ . '/../app/bootstrap.php';
require __DIR__ . '/../app/mistral.php';

$limit = isset($argv[1]) && ctype_digit($argv[1]) ? (int) $argv[1] : 10;
$limit = max(1, min($limit, 100));
$st = db()->prepare("SELECT id FROM content_posts WHERE status='pending_review' ORDER BY created_at ASC LIMIT :limit");
$st->bindValue(':limit', $limit, PDO::PARAM_INT);
$st->execute();
$ids = $st->fetchAll(PDO::FETCH_COLUMN);

$processed = 0;
foreach ($ids as $contentId) {
    try {
        $decision = process_content_safety_review((int) $contentId);
        if ($decision !== 'skipped') $processed++;
        echo "Conteúdo {$contentId}: {$decision}.\n";
    } catch (Throwable) {
        fwrite(STDERR, "Conteúdo {$contentId}: análise não concluída; permanece bloqueado.\n");
    }
}
echo "Fila finalizada: {$processed} item(ns) processado(s).\n";
