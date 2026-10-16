<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') exit("Somente CLI.\n");
require __DIR__ . '/../app/bootstrap.php';
require __DIR__ . '/../app/mistral.php';
$contentId = isset($argv[1]) && ctype_digit($argv[1]) ? (int) $argv[1] : 0;
if (!$contentId) exit("Uso: php bin/process-content-safety.php <content-id>\n");

try {
    $decision = process_content_safety_review($contentId);
    echo "Análise concluída: {$decision}.\n";
} catch (Throwable) { fwrite(STDERR,"Análise não concluída; conteúdo permanece bloqueado.\n"); exit(1); }
