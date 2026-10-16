<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') exit("Somente CLI.\n");
require __DIR__ . '/../app/bootstrap.php';
require __DIR__ . '/../app/mistral.php';
$contentId = isset($argv[1]) && ctype_digit($argv[1]) ? (int) $argv[1] : 0;
if (!$contentId) exit("Uso: php bin/process-content-safety.php <content-id>\n");

try {
    $st=db()->prepare('SELECT cm.storage_key,cm.mime_type FROM content_media cm WHERE cm.content_id=:id ORDER BY cm.id LIMIT 1'); $st->execute(['id'=>$contentId]); $media=$st->fetch();
    $result=$media ? mistral_image_safety_assessment((string)media_storage_path($media['storage_key']),$media['mime_type']) : ['decision'=>'manual_review','signals'=>['no_image_for_automated_review']];
    db()->beginTransaction();
    db()->prepare("INSERT INTO content_safety_reviews(content_id,provider,decision,signals,reviewed_at) VALUES (:id,'mistral',:decision,:signals,NOW()) ON CONFLICT (content_id) DO UPDATE SET provider=EXCLUDED.provider,decision=EXCLUDED.decision,signals=EXCLUDED.signals,reviewed_at=NOW()")
        ->execute(['id'=>$contentId,'decision'=>$result['decision'],'signals'=>json_encode($result['signals'], JSON_THROW_ON_ERROR)]);
    if ($result['decision']==='approved') db()->prepare("UPDATE content_posts SET status='published' WHERE id=:id AND status='pending_review'")->execute(['id'=>$contentId]);
    else db()->prepare("UPDATE content_posts SET status='manual_review' WHERE id=:id")->execute(['id'=>$contentId]);
    db()->commit(); echo "Análise concluída: {$result['decision']}.\n";
} catch (Throwable) { if (db()->inTransaction()) db()->rollBack(); fwrite(STDERR,"Análise não concluída; conteúdo permanece bloqueado.\n"); exit(1); }
