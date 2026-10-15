-- Executar após schema.sql. Senha de todos os usuários de demonstração: mymatch123
INSERT INTO users (email,password_hash,birth_date) VALUES
('ana@mymatch.local','$2y$10$tmthIrVPuHMHWMfkw3oCgOgg3egxY8WwbXKky.20xV4H8eDftrz2y','1995-05-10'),
('bruno@mymatch.local','$2y$10$tmthIrVPuHMHWMfkw3oCgOgg3egxY8WwbXKky.20xV4H8eDftrz2y','1992-09-18'),
('carla@mymatch.local','$2y$10$tmthIrVPuHMHWMfkw3oCgOgg3egxY8WwbXKky.20xV4H8eDftrz2y','1998-02-14');
UPDATE user_settings SET content_enabled=true,dating_enabled=true,integration_enabled=true,visitor_identity_consent=true;
INSERT INTO content_profiles(user_id,display_name,bio) SELECT id, CASE email WHEN 'ana@mymatch.local' THEN 'Ana Studio' WHEN 'bruno@mymatch.local' THEN 'Bruno Criativo' ELSE 'Carla' END, 'Criador(a) de conteúdo.' FROM users;
INSERT INTO relationship_profiles(user_id,display_name,bio,city,is_active) SELECT id, CASE email WHEN 'ana@mymatch.local' THEN 'Ana' WHEN 'bruno@mymatch.local' THEN 'Bruno' ELSE 'Carla' END, 'Aberto(a) a novas conexões, com respeito e leveza.', 'São Paulo', true FROM users;
INSERT INTO content_posts(producer_id,title,description,access_type,status) SELECT id,'Boas-vindas','Conteúdo de demonstração','free','published' FROM users WHERE email='ana@mymatch.local';
INSERT INTO content_accesses(content_id,viewer_id,is_valid) SELECT p.id,u.id,true FROM content_posts p CROSS JOIN users u WHERE u.email='bruno@mymatch.local';
