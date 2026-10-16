<?php
declare(strict_types=1);

function mistral_request(string $path, array $payload): array
{
    $handle = curl_init('https://api.mistral.ai' . $path);
    curl_setopt_array($handle, [
        CURLOPT_POST => true, CURLOPT_POSTFIELDS => json_encode($payload, JSON_THROW_ON_ERROR),
        CURLOPT_HTTPHEADER => ['Content-Type: application/json', 'Authorization: Bearer ' . vault_secret('mistral.api_key')],
        CURLOPT_RETURNTRANSFER => true, CURLOPT_CONNECTTIMEOUT => 10, CURLOPT_TIMEOUT => 45,
    ]);
    $body = curl_exec($handle); $status = (int) curl_getinfo($handle, CURLINFO_RESPONSE_CODE); curl_close($handle);
    if (!is_string($body) || $status < 200 || $status >= 300) throw new RuntimeException('Serviço de análise indisponível.');
    return json_decode($body, true, 512, JSON_THROW_ON_ERROR);
}

function mistral_image_safety_assessment(string $path, string $mime): array
{
    if (!in_array($mime, ['image/jpeg','image/png','image/webp'], true) || !is_file($path) || filesize($path) > 8 * 1024 * 1024) {
        return ['decision'=>'manual_review','signals'=>['unsupported_or_oversized_media']];
    }
    $instruction = 'Classifique a imagem para segurança de plataforma. Retorne APENAS JSON válido: {"decision":"approved"|"manual_review","signals":[string]}. Use manual_review se houver qualquer indício ou incerteza sobre pessoa menor de idade, nudez/sexualização, coerção, exploração, violência, abuso, violência contra mulher, conteúdo sexual explícito, documento de identidade, ou baixa confiança. Nunca aprove em caso de dúvida.';
    $response = mistral_request('/v1/chat/completions', ['model'=>'mistral-small-latest','temperature'=>0,'max_tokens'=>180,'messages'=>[['role'=>'user','content'=>[['type'=>'text','text'=>$instruction],['type'=>'image_url','image_url'=>'data:' . $mime . ';base64,' . base64_encode((string) file_get_contents($path))]]]]]);
    $text = $response['choices'][0]['message']['content'] ?? '';
    if (!is_string($text)) return ['decision'=>'manual_review','signals'=>['invalid_provider_response']];
    $result = json_decode(trim(preg_replace('/^```(?:json)?|```$/m', '', $text)), true);
    $signals = is_array($result['signals'] ?? null) ? array_values(array_filter($result['signals'], 'is_string')) : ['invalid_provider_response'];
    $decision = ($result['decision'] ?? '') === 'approved' && !$signals ? 'approved' : 'manual_review';
    return ['decision'=>$decision,'signals'=>$signals];
}

function mistral_ocr_document(string $path, string $mime): array
{
    if (!is_file($path) || filesize($path) > 10 * 1024 * 1024) throw new RuntimeException('Documento indisponível para análise.');
    $type = str_starts_with($mime, 'image/') ? 'image_url' : 'document_url';
    return mistral_request('/v1/ocr', ['model'=>'mistral-ocr-latest','document'=>['type'=>$type, $type=>'data:' . $mime . ';base64,' . base64_encode((string) file_get_contents($path))], 'confidence_scores_granularity'=>'page']);
}
