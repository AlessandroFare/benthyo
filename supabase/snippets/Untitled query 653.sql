-- Verifica prima
SELECT id, scientific_name, common_name FROM species WHERE common_name IN ('American sweetgum', 'Monk Parakeet');
-- Poi correggi il common_name a NULL per riresolverlo alla prossima run
UPDATE species SET common_name = NULL, image_url = NULL WHERE common_name IN ('American sweetgum', 'Monk Parakeet');