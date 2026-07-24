/* 
   ЭТАП 1. СОЗДАНИЕ И ЗАПОЛНЕНИЕ БД
*/


CREATE SCHEMA raw_data;

CREATE TABLE raw_data.sales (
    id INTEGER,
    auto VARCHAR,
    gasoline_consumption VARCHAR, 
    price VARCHAR,                
    date DATE,
    person_name VARCHAR,
    phone VARCHAR,
    discount VARCHAR,
    brand_origin VARCHAR
);



CREATE SCHEMA car_shop;


CREATE TABLE car_shop.countries (
    country_id SERIAL PRIMARY KEY,
    country_name VARCHAR UNIQUE
);


CREATE TABLE car_shop.brands (
    brand_id SERIAL PRIMARY KEY,
    brand_name VARCHAR NOT NULL UNIQUE, 
    country_id INTEGER REFERENCES car_shop.countries(country_id) 
);


CREATE TABLE car_shop.models (
    model_id SERIAL PRIMARY KEY,
    model_name VARCHAR NOT NULL, 
    brand_id INTEGER NOT NULL REFERENCES car_shop.brands(brand_id),
    gasoline_consumption NUMERIC(4,1), 
    UNIQUE (model_name, brand_id)
);


CREATE TABLE car_shop.colors (
    color_id SERIAL PRIMARY KEY,
    color_name VARCHAR NOT NULL UNIQUE 
);


CREATE TABLE car_shop.model_colors (
    model_id INTEGER NOT NULL REFERENCES car_shop.models(model_id),
    color_id INTEGER NOT NULL REFERENCES car_shop.colors(color_id),
    PRIMARY KEY (model_id, color_id) 
);


CREATE TABLE car_shop.clients (
    client_id SERIAL PRIMARY KEY,
    person_name VARCHAR NOT NULL, 
    phone VARCHAR NOT NULL UNIQUE 
);


CREATE TABLE car_shop.sales (
    sale_id SERIAL PRIMARY KEY,
    model_id INTEGER NOT NULL REFERENCES car_shop.models(model_id),
    color_id INTEGER NOT NULL REFERENCES car_shop.colors(color_id), 
    client_id INTEGER NOT NULL REFERENCES car_shop.clients(client_id),
    sale_date DATE NOT NULL, 
    price NUMERIC(9,2) NOT NULL, 
    discount SMALLINT NOT NULL DEFAULT 0 
);



INSERT INTO car_shop.countries (country_name)
SELECT DISTINCT brand_origin
FROM raw_data.sales;


UPDATE car_shop.countries
SET country_name = NULL
WHERE country_name = 'null';


INSERT INTO car_shop.brands (brand_name, country_id)
SELECT DISTINCT
    split_part(auto, ' ', 1) AS brand_name,
    c.country_id
FROM raw_data.sales s
JOIN car_shop.countries c
    ON c.country_name = s.brand_origin
    OR (c.country_name IS NULL AND s.brand_origin = 'null');


INSERT INTO car_shop.colors (color_name)
SELECT DISTINCT trim(split_part(auto, ',', 2)) AS color_name
FROM raw_data.sales;


INSERT INTO car_shop.models (model_name, brand_id, gasoline_consumption)
SELECT DISTINCT
    trim(substring(split_part(s.auto, ',', 1) FROM length(split_part(s.auto, ' ', 1)) + 2)) AS model_name,
    b.brand_id,
    CASE WHEN s.gasoline_consumption = 'null' THEN NULL ELSE s.gasoline_consumption::numeric END
FROM raw_data.sales s
JOIN car_shop.brands b ON b.brand_name = split_part(s.auto, ' ', 1);


INSERT INTO car_shop.model_colors (model_id, color_id)
SELECT DISTINCT
    m.model_id,
    col.color_id
FROM raw_data.sales s
JOIN car_shop.brands b ON b.brand_name = split_part(s.auto, ' ', 1)
JOIN car_shop.models m ON m.brand_id = b.brand_id
    AND m.model_name = trim(substring(split_part(s.auto, ',', 1) FROM length(split_part(s.auto, ' ', 1)) + 2))
JOIN car_shop.colors col ON col.color_name = trim(split_part(s.auto, ',', 2));


INSERT INTO car_shop.clients (person_name, phone)
SELECT DISTINCT person_name, phone
FROM raw_data.sales;


INSERT INTO car_shop.sales (model_id, color_id, client_id, sale_date, price, discount)
SELECT
    m.model_id,
    col.color_id,
    cl.client_id,
    s.date,
    s.price::numeric,
    s.discount::smallint
FROM raw_data.sales s
JOIN car_shop.brands b ON b.brand_name = split_part(s.auto, ' ', 1)
JOIN car_shop.models m ON m.brand_id = b.brand_id
    AND m.model_name = trim(substring(split_part(s.auto, ',', 1) FROM length(split_part(s.auto, ' ', 1)) + 2))
JOIN car_shop.colors col ON col.color_name = trim(split_part(s.auto, ',', 2))
JOIN car_shop.clients cl ON cl.person_name = s.person_name AND cl.phone = s.phone;


/* 
   ЭТАП 2. СОЗДАНИЕ ВЫБОРОК
 */

/* ---------- Задание 1. Процент моделей без gasoline_consumption ---------- */

SELECT
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE gasoline_consumption IS NULL) / COUNT(*),
        2
    ) AS nulls_percentage_gasoline_consumption
FROM car_shop.models;

/* ---------- Задание 2. Средняя цена по бренду и году (с учётом скидки) ---------- */

SELECT
    b.brand_name,
    EXTRACT(YEAR FROM s.sale_date)::int AS year,
    ROUND(AVG(s.price), 2) AS price_avg
FROM car_shop.sales s
JOIN car_shop.models m ON m.model_id = s.model_id
JOIN car_shop.brands b ON b.brand_id = m.brand_id
GROUP BY b.brand_name, EXTRACT(YEAR FROM s.sale_date)
ORDER BY b.brand_name, year;

/* ---------- Задание 3. Средняя цена по месяцам 2022 года (с учётом скидки) ---------- */

SELECT
    EXTRACT(MONTH FROM s.sale_date)::int AS month,
    EXTRACT(YEAR FROM s.sale_date)::int AS year,
    ROUND(AVG(s.price), 2) AS price_avg
FROM car_shop.sales s
WHERE EXTRACT(YEAR FROM s.sale_date) = 2022
GROUP BY EXTRACT(MONTH FROM s.sale_date), EXTRACT(YEAR FROM s.sale_date)
ORDER BY month;

/* ---------- Задание 4. Список купленных машин по каждому клиенту ---------- */

SELECT
    cl.person_name AS person,
    STRING_AGG(b.brand_name || ' ' || m.model_name, ', ') AS cars
FROM car_shop.sales s
JOIN car_shop.clients cl ON cl.client_id = s.client_id
JOIN car_shop.models m ON m.model_id = s.model_id
JOIN car_shop.brands b ON b.brand_id = m.brand_id
GROUP BY cl.person_name
ORDER BY cl.person_name;

/* ---------- Задание 5. Макс/мин цена по стране без учёта скидки ---------- */

SELECT
    co.country_name AS brand_origin,
    ROUND(MAX(s.price / (1 - s.discount::numeric / 100)), 2) AS price_max,
    ROUND(MIN(s.price / (1 - s.discount::numeric / 100)), 2) AS price_min
FROM car_shop.sales s
JOIN car_shop.models m ON m.model_id = s.model_id
JOIN car_shop.brands b ON b.brand_id = m.brand_id
JOIN car_shop.countries co ON co.country_id = b.country_id
GROUP BY co.country_name
ORDER BY co.country_name;

/* ---------- Задание 6. Количество клиентов из США (телефон начинается на +1) ---------- */

SELECT
    COUNT(*) AS persons_from_usa_count
FROM car_shop.clients
WHERE phone LIKE '+1%';
