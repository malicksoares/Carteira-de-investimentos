INSERT INTO users (id, username, password_hash)
VALUES (1, 'trader', 'dummy-hash-for-tests');

INSERT INTO assets (id, user_id, name, category, quantity, unit_value)
VALUES (1, 1, 'Bitcoin', 'Cripto', 2, 10.0);

SELECT setval('assets_id_seq', (SELECT MAX(id) FROM assets));
SELECT setval('users_id_seq', (SELECT MAX(id) FROM users));
