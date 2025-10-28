-- Включаем pgcrypto
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

-- Включаем pgaudit
CREATE EXTENSION IF NOT EXISTS pgaudit WITH SCHEMA public;



-- Создание схем
CREATE SCHEMA app;
COMMENT ON SCHEMA app IS 'Бизнес-данные';

CREATE SCHEMA ref;
COMMENT ON SCHEMA ref IS 'Справочники';

CREATE SCHEMA audit;
COMMENT ON SCHEMA audit IS 'Аудит';

CREATE SCHEMA stg;
COMMENT ON SCHEMA stg IS 'Временные/обслуживающие';

-- Отнимем права у роли PUBLIC на схемы, зпрещаем создавать новые схемы
REVOKE ALL ON SCHEMA public, app, ref, audit, stg FROM PUBLIC;
REVOKE CREATE ON DATABASE admin FROM PUBLIC;


-- Создание ролей

-- app_owner
CREATE ROLE app_owner WITH 
  NOLOGIN 
  NOINHERIT;
COMMENT ON ROLE app_owner IS 'Роль-владелец для всех объектов';   

GRANT CONNECT ON DATABASE admin TO app_owner;
GRANT CREATE ON DATABASE admin TO app_owner;
GRANT USAGE ON SCHEMA public TO app_owner;
GRANT EXECUTE ON FUNCTION pgp_sym_encrypt(text, text) TO app_owner;
GRANT EXECUTE ON FUNCTION pgp_sym_decrypt(bytea, text) TO app_owner;

-- Назначение роли владельцем существующих схем
ALTER SCHEMA app OWNER TO app_owner;
ALTER SCHEMA ref OWNER TO app_owner;
ALTER SCHEMA audit OWNER TO app_owner;
ALTER SCHEMA stg OWNER TO app_owner;

-- app_writer
CREATE ROLE app_writer WITH
  LOGIN
  NOINHERIT
  PASSWORD 'app_writer123';

COMMENT ON ROLE app_writer IS 'Роль с правами на чтение/запись';

GRANT CONNECT ON DATABASE admin TO app_writer;

GRANT USAGE ON SCHEMA app, ref, audit TO app_writer;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app, ref TO app_writer;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app, ref
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_writer;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO app_writer;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA ref
  GRANT USAGE, SELECT ON SEQUENCES TO app_writer;


-- app_reader
CREATE ROLE app_reader WITH
  LOGIN
  NOINHERIT
  PASSWORD 'app_reader123';

COMMENT ON ROLE app_reader IS 'Роль для чтения данных из схем app и ref';

GRANT CONNECT ON DATABASE admin TO app_reader;
GRANT USAGE ON SCHEMA app, ref, audit TO app_reader;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app, ref
  GRANT SELECT ON TABLES TO app_reader;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app, ref
  GRANT SELECT ON SEQUENCES TO app_reader;


-- auditor
CREATE ROLE auditor WITH
  LOGIN
  NOINHERIT
  PASSWORD 'auditor123';

COMMENT ON ROLE auditor IS 'Роль для аудита';

ALTER ROLE auditor WITH BYPASSRLS; -- Позволяет игнорировать политику RLS
GRANT CONNECT ON DATABASE admin TO auditor;
GRANT USAGE ON SCHEMA app, ref, audit, stg TO auditor;

GRANT SELECT ON ALL TABLES IN SCHEMA app, ref, audit, stg TO auditor;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA app, ref, audit, stg TO auditor;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app, ref, audit, stg
  GRANT SELECT ON TABLES TO auditor;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app, ref, audit, stg
  GRANT SELECT ON SEQUENCES TO auditor;

-- ddl_admin
CREATE ROLE ddl_admin WITH
  LOGIN
  NOINHERIT
  PASSWORD 'ddl_admin123';

COMMENT ON ROLE ddl_admin IS 'Роль для выполнения DDL-операций';
GRANT app_owner TO ddl_admin;

-- dml_admin
CREATE ROLE dml_admin WITH
  LOGIN
  NOINHERIT
  PASSWORD 'dml_admin123';

COMMENT ON ROLE dml_admin IS 'Роль для выполнения DML-операций';

GRANT USAGE ON SCHEMA app, ref, stg, audit TO dml_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app, ref, stg TO dml_admin;
GRANT CONNECT ON DATABASE admin TO dml_admin;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app, ref, stg
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO dml_admin;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app, ref, stg
  GRANT USAGE ON SEQUENCES TO dml_admin;

-- security_admin
CREATE ROLE security_admin WITH
  LOGIN
  NOINHERIT
  NOCREATEDB
  CREATEROLE
  NOREPLICATION
  PASSWORD 'security_admin123';

COMMENT ON ROLE security_admin IS 'Роль для управления другими ролями';

GRANT CONNECT ON DATABASE admin TO security_admin;
GRANT USAGE ON SCHEMA app, ref, audit TO security_admin;

---------------------------------------------------------------------------------
-- объявление таблиц

SET ROLE app_owner;


-- ref

-- Статусы посылок
CREATE TABLE ref.parcel_statuses (
    id SERIAL PRIMARY KEY,
    status_name VARCHAR(50) NOT NULL UNIQUE
);
COMMENT ON TABLE ref.parcel_statuses IS 'Справочник: Статусы посылок';

-- Типы отделов
CREATE TABLE ref.department_types (
    id SERIAL PRIMARY KEY,
    type_name VARCHAR(100) NOT NULL UNIQUE
);
COMMENT ON TABLE ref.department_types IS 'Справочник: Типы отделов';

-- Должности
CREATE TABLE ref.positions (
    id SERIAL PRIMARY KEY,
    position_name VARCHAR(100) NOT NULL UNIQUE
);
COMMENT ON TABLE ref.positions IS 'Справочник: Должности сотрудников';

-- Статусы сотрудников
CREATE TABLE ref.employee_statuses (
    id SERIAL PRIMARY KEY,
    status_name VARCHAR(50) NOT NULL UNIQUE
);
COMMENT ON TABLE ref.employee_statuses IS 'Справочник: Статусы сотрудников';

--app
-- Клиенты
CREATE TABLE app.clients (
    id SERIAL PRIMARY KEY,
    last_name VARCHAR(100) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    phone bytea NOT NULL,
    address text NOT NULL
);
COMMENT ON TABLE app.clients IS 'Данные клиентов';

-- Отделы
CREATE TABLE app.departments (
    id SERIAL PRIMARY KEY,
    department_type_id INT NOT NULL REFERENCES ref.department_types(id) ON DELETE RESTRICT,
    zip_code VARCHAR(10) NOT NULL,
    city VARCHAR(200) NOT NULL,
    address TEXT NOT NULL,
    UNIQUE (zip_code, address)
);
COMMENT ON TABLE app.departments IS 'Почтовые отделения, сортировочные центры, склады';

-- Сотрудники
CREATE TABLE app.employees (
    id SERIAL PRIMARY KEY,
    last_name VARCHAR(100) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    department_id INT NOT NULL REFERENCES app.departments(id) ON DELETE RESTRICT,
    position_id INT NOT NULL REFERENCES ref.positions(id) ON DELETE RESTRICT,
    status_id INT NOT NULL REFERENCES ref.employee_statuses(id) ON DELETE RESTRICT,
    login VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(100) NOT NULL
);
COMMENT ON TABLE app.employees IS 'Сотрудники';


-- Сегменты маршрутов
CREATE TABLE app.route_segments (
    id SERIAL PRIMARY KEY,
    departure_department_id INT NOT NULL REFERENCES app.departments(id) ON DELETE RESTRICT,
    arrival_department_id INT NOT NULL REFERENCES app.departments(id) ON DELETE RESTRICT,
    expected_time INTERVAL,
    CONSTRAINT check_different_departments CHECK (departure_department_id <> arrival_department_id)
);
COMMENT ON TABLE app.route_segments IS 'Сегменты маршрута между отделами';

-- Посылки
CREATE TABLE app.parcels (
    id SERIAL PRIMARY KEY,
    tracking_number VARCHAR(20) NOT NULL UNIQUE,
    sender_client_id INT NOT NULL REFERENCES app.clients(id) ON DELETE RESTRICT,
    recipient_client_id INT NOT NULL REFERENCES app.clients(id) ON DELETE RESTRICT,
    departure_department_id INT NOT NULL REFERENCES app.departments(id) ON DELETE RESTRICT,
    arrival_department_id INT NOT NULL REFERENCES app.departments(id) ON DELETE RESTRICT,
    weight_kg NUMERIC(10, 3) NOT NULL,
    declared_value NUMERIC(12, 2) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT check_weight_positive CHECK (weight_kg > 0),
    CONSTRAINT check_declared_value_non_negative CHECK (declared_value >= 0)
);
COMMENT ON TABLE app.parcels IS 'Информация о посылках';


-- Перемещения посылок
CREATE TABLE app.parcel_movements (
    id SERIAL PRIMARY KEY,
    parcel_id INT NOT NULL REFERENCES app.parcels(id) ON DELETE CASCADE,
    segment_id INT NOT NULL REFERENCES app.route_segments(id) ON DELETE RESTRICT,
    employee_id INT NOT NULL REFERENCES app.employees(id) ON DELETE RESTRICT,
    status_id INT NOT NULL REFERENCES ref.parcel_statuses(id) ON DELETE RESTRICT,
    event_timestamp TIMESTAMP NOT NULL DEFAULT now()
);
COMMENT ON TABLE app.parcel_movements IS 'История перемещений посылок';

RESET ROLE;

-----------------------------------------------------------------------------
-- Заполненеие справочников

INSERT INTO ref.parcel_statuses (status_name) VALUES
('Зарегистрировано'),
('Принято в отделении отправки'),
('В пути'),
('Прошло сортировку'),
('Прибыло в город назначения'),
('Передано курьеру для доставки'),
('Ожидает в пункте выдачи'),
('Вручено получателю'),
('Возвращено отправителю'),
('Утеряно');


INSERT INTO ref.department_types (type_name) VALUES
('Почтовое отделение'),
('Сортировочный центр'),
('Пункт выдачи заказов'),
('Склад');


INSERT INTO ref.positions (position_name) VALUES
('Оператор связи'),
('Сортировщик'),
('Начальник отделения'),
('Специалист по логистике'),
('Курьер'),
('Администратор БД');


INSERT INTO ref.employee_statuses (status_name) VALUES
('Активен'),
('В отпуске'),
('На больничном'),
('Уволен');


----------------------------------------------------------------------------------
-- Заполнение ключевых таблиц

SET session.encryption_key = 'ABOBA';

INSERT INTO app.departments (department_type_id, zip_code, city, address) VALUES
((SELECT id FROM ref.department_types WHERE type_name = 'Почтовое отделение'), '101000', 'Москва', 'ул. Мясницкая, д. 26'),
((SELECT id FROM ref.department_types WHERE type_name = 'Почтовое отделение'), '190000', 'Санкт-Петербург', 'ул. Почтамтская, д. 9'),
((SELECT id FROM ref.department_types WHERE type_name = 'Почтовое отделение'), '620014', 'Екатеринбург', 'просп. Ленина, д. 39'),
((SELECT id FROM ref.department_types WHERE type_name = 'Почтовое отделение'), '630099', 'Новосибирск', 'ул. Советская, д. 33'),
((SELECT id FROM ref.department_types WHERE type_name = 'Сортировочный центр'), '140961', 'Подольск', 'Московский АСЦ'),
((SELECT id FROM ref.department_types WHERE type_name = 'Сортировочный центр'), '630960', 'Новосибирск', 'Новосибирский МСЦ'),
((SELECT id FROM ref.department_types WHERE type_name = 'Пункт выдачи заказов'), '125009', 'Москва', 'ул. Тверская, д. 4'),
((SELECT id FROM ref.department_types WHERE type_name = 'Пункт выдачи заказов'), '191025', 'Санкт-Петербург', 'Невский просп., д. 71'),
((SELECT id FROM ref.department_types WHERE type_name = 'Почтовое отделение'), '420111', 'Казань', 'ул. Кремлевская, д. 8'),
((SELECT id FROM ref.department_types WHERE type_name = 'Сортировочный центр'), '420300', 'Казань', 'ЛПЦ Внуково-Казанский Приволжский');


INSERT INTO app.clients (last_name, first_name, middle_name, phone, address) VALUES
('Иванов', 'Иван', 'Иванович', pgp_sym_encrypt('89161234567', current_setting('session.encryption_key')), pgp_sym_encrypt('г. Москва, ул. Ленина, д. 1, кв. 10', current_setting('session.encryption_key'))),
('Петрова', 'Анна', 'Сергеевна', pgp_sym_encrypt('89267654321', current_setting('session.encryption_key')), pgp_sym_encrypt('г. Москва, ул. Тверская, д. 5, кв. 25', current_setting('session.encryption_key'))),
('Сидоров', 'Петр', 'Николаевич', pgp_sym_encrypt('89031112233', current_setting('session.encryption_key')), pgp_sym_encrypt('г. Санкт-Петербург, Невский пр-т, д. 100, кв. 1', current_setting('session.encryption_key'))),
('Смирнова', 'Ольга', 'Владимировна', pgp_sym_encrypt('89119876543', current_setting('session.encryption_key')), pgp_sym_encrypt('г. Санкт-Петербург, ул. Садовая, д. 22, кв. 44', current_setting('session.encryption_key'))),
('Кузнецов', 'Дмитрий', 'Алексеевич', pgp_sym_encrypt('89995556677', current_setting('session.encryption_key')), pgp_sym_encrypt('г. Екатеринбург, ул. Малышева, д. 80, кв. 12', current_setting('session.encryption_key'))),
('Васильева', 'Екатерина', 'Игоревна', pgp_sym_encrypt('89823334455', current_setting('session.encryption_key')), pgp_sym_encrypt('г. Екатеринбург, ул. 8 Марта, д. 5, кв. 3', current_setting('session.encryption_key'))),
('Попов', 'Михаил', 'Юрьевич', pgp_sym_encrypt('89051239876', current_setting('session.encryption_key')), pgp_sym_encrypt('г. Новосибирск, Красный пр-т, д. 65, кв. 56', current_setting('session.encryption_key'))),
('Лебедева', 'Мария', 'Павловна', pgp_sym_encrypt('89135551122', current_setting('session.encryption_key')), pgp_sym_encrypt('г. Новосибирск, ул. Вокзальная магистраль, д. 1, кв. 8', current_setting('session.encryption_key'))),
('Козлов', 'Артем', 'Викторович', pgp_sym_encrypt('89257778899', current_setting('session.encryption_key')), pgp_sym_encrypt('г. Казань, ул. Баумана, д. 40, кв. 2', current_setting('session.encryption_key'))),
('Новикова', 'Алиса', 'Денисовна', pgp_sym_encrypt('89172345678', current_setting('session.encryption_key')), pgp_sym_encrypt('г. Казань, ул. Петербургская, д. 9, кв. 7', current_setting('session.encryption_key'))),
('Федоров', 'Роман', 'Григорьевич', pgp_sym_encrypt('89261122334', current_setting('session.encryption_key')), pgp_sym_encrypt('г. Москва, ул. Арбат, д. 15, кв. 99', current_setting('session.encryption_key')));


INSERT INTO app.employees (last_name, first_name, department_id, position_id, status_id, login, password_hash) VALUES
('Максимова', 'Марина', (SELECT id FROM app.departments WHERE zip_code = '101000'), (SELECT id FROM ref.positions WHERE position_name = 'Оператор связи'), (SELECT id FROM ref.employee_statuses WHERE status_name = 'Активен'), 'marina.m', crypt('password123', gen_salt('bf'))),
('Соколов', 'Сергей', (SELECT id FROM app.departments WHERE zip_code = '101000'), (SELECT id FROM ref.positions WHERE position_name = 'Начальник отделения'), (SELECT id FROM ref.employee_statuses WHERE status_name = 'Активен'), 'sergey.s', crypt('password123', gen_salt('bf'))),
('Волков', 'Владимир', (SELECT id FROM app.departments WHERE zip_code = '190000'), (SELECT id FROM ref.positions WHERE position_name = 'Оператор связи'), (SELECT id FROM ref.employee_statuses WHERE status_name = 'Активен'), 'vladimir.v', crypt('password123', gen_salt('bf'))),
('Зайцева', 'Дарья', (SELECT id FROM app.departments WHERE zip_code = '140961'), (SELECT id FROM ref.positions WHERE position_name = 'Сортировщик'), (SELECT id FROM ref.employee_statuses WHERE status_name = 'Активен'), 'daria.z', crypt('password123', gen_salt('bf'))),
('Орлов', 'Олег', (SELECT id FROM app.departments WHERE zip_code = '140961'), (SELECT id FROM ref.positions WHERE position_name = 'Специалист по логистике'), (SELECT id FROM ref.employee_statuses WHERE status_name = 'Активен'), 'oleg.o', crypt('password123', gen_salt('bf'))),
('Белова', 'Виктория', (SELECT id FROM app.departments WHERE zip_code = '620014'), (SELECT id FROM ref.positions WHERE position_name = 'Оператор связи'), (SELECT id FROM ref.employee_statuses WHERE status_name = 'Активен'), 'victoria.b', crypt('password123', gen_salt('bf'))),
('Давыдов', 'Денис', (SELECT id FROM app.departments WHERE zip_code = '630099'), (SELECT id FROM ref.positions WHERE position_name = 'Оператор связи'), (SELECT id FROM ref.employee_statuses WHERE status_name = 'Активен'), 'denis.d', crypt('password123', gen_salt('bf'))),
('Тихонова', 'Татьяна', (SELECT id FROM app.departments WHERE zip_code = '630960'), (SELECT id FROM ref.positions WHERE position_name = 'Сортировщик'), (SELECT id FROM ref.employee_statuses WHERE status_name = 'Активен'), 'tatiana.t', crypt('password123', gen_salt('bf'))),
('Степанов', 'Станислав', (SELECT id FROM app.departments WHERE zip_code = '420111'), (SELECT id FROM ref.positions WHERE position_name = 'Оператор связи'), (SELECT id FROM ref.employee_statuses WHERE status_name = 'Активен'), 'stanislav.s', crypt('password123', gen_salt('bf'))),
('Романова', 'Регина', (SELECT id FROM app.departments WHERE zip_code = '420300'), (SELECT id FROM ref.positions WHERE position_name = 'Сортировщик'), (SELECT id FROM ref.employee_statuses WHERE status_name = 'Активен'), 'regina.r', crypt('password123', gen_salt('bf')));


INSERT INTO app.route_segments (departure_department_id, arrival_department_id, expected_time) VALUES
-- Москва -> Подольск СЦ
((SELECT id FROM app.departments WHERE zip_code = '101000'), (SELECT id FROM app.departments WHERE zip_code = '140961'), '8 hours'),
-- Подольск СЦ -> СПб
((SELECT id FROM app.departments WHERE zip_code = '140961'), (SELECT id FROM app.departments WHERE zip_code = '190000'), '1 day'),
-- СПб -> Подольск СЦ
((SELECT id FROM app.departments WHERE zip_code = '190000'), (SELECT id FROM app.departments WHERE zip_code = '140961'), '1 day'),
-- Подольск СЦ -> Новосибирск СЦ
((SELECT id FROM app.departments WHERE zip_code = '140961'), (SELECT id FROM app.departments WHERE zip_code = '630960'), '3 days'),
-- Новосибирск СЦ -> Новосибирск Отделение
((SELECT id FROM app.departments WHERE zip_code = '630960'), (SELECT id FROM app.departments WHERE zip_code = '630099'), '6 hours'),
-- Новосибирск Отделение -> Новосибирск СЦ
((SELECT id FROM app.departments WHERE zip_code = '630099'), (SELECT id FROM app.departments WHERE zip_code = '630960'), '6 hours'),
-- Подольск СЦ -> Екатеринбург
((SELECT id FROM app.departments WHERE zip_code = '140961'), (SELECT id FROM app.departments WHERE zip_code = '620014'), '2 days'),
-- Екатеринбург -> Подольск СЦ
((SELECT id FROM app.departments WHERE zip_code = '620014'), (SELECT id FROM app.departments WHERE zip_code = '140961'), '2 days'),
-- Подольск СЦ -> Казань СЦ
((SELECT id FROM app.departments WHERE zip_code = '140961'), (SELECT id FROM app.departments WHERE zip_code = '420300'), '18 hours'),
-- Казань СЦ -> Казань Отделение
((SELECT id FROM app.departments WHERE zip_code = '420300'), (SELECT id FROM app.departments WHERE zip_code = '420111'), '4 hours');


INSERT INTO app.parcels (tracking_number, sender_client_id, recipient_client_id, departure_department_id, arrival_department_id, weight_kg, declared_value) VALUES
('RR000000001RU', 1, 3, 1, 2, 1.5, 1000),
('RR000000002RU', 4, 1, 2, 1, 0.8, 500),
('RR000000003RU', 2, 7, 1, 4, 5.2, 15000),
('RR000000004RU', 8, 5, 4, 3, 2.1, 2500),
('RR000000005RU', 6, 9, 3, 9, 0.5, 300),
('RR000000006RU', 10, 1, 9, 1, 10.0, 50000),
('RR000000007RU', 1, 8, 1, 4, 3.0, 7000),
('RR000000008RU', 3, 6, 2, 3, 1.2, 1200),
('RR000000009RU', 5, 2, 3, 1, 0.9, 900),
('RR000000010RU', 7, 10, 4, 9, 4.5, 4500);


INSERT INTO app.parcel_movements (parcel_id, segment_id, employee_id, status_id, event_timestamp) VALUES
(1, 1, 1, (SELECT id FROM ref.parcel_statuses WHERE status_name = 'Зарегистрировано'), now() - interval '3 days'),
(1, 1, 1, (SELECT id FROM ref.parcel_statuses WHERE status_name = 'Принято в отделении отправки'), now() - interval '2 days 12 hours'),
(1, 2, 4, (SELECT id FROM ref.parcel_statuses WHERE status_name = 'В пути'), now() - interval '2 days'),
(1, 2, 5, (SELECT id FROM ref.parcel_statuses WHERE status_name = 'Прибыло в город назначения'), now() - interval '1 day');


INSERT INTO app.parcel_movements (parcel_id, segment_id, employee_id, status_id, event_timestamp) VALUES
(3, 1, 2, (SELECT id FROM ref.parcel_statuses WHERE status_name = 'Зарегистрировано'), now() - interval '5 days'),
(3, 1, 1, (SELECT id FROM ref.parcel_statuses WHERE status_name = 'Принято в отделении отправки'), now() - interval '5 days'),
(3, 4, 4, (SELECT id FROM ref.parcel_statuses WHERE status_name = 'В пути'), now() - interval '4 days'),
(3, 4, 8, (SELECT id FROM ref.parcel_statuses WHERE status_name = 'Прошло сортировку'), now() - interval '2 days'),
(3, 5, 8, (SELECT id FROM ref.parcel_statuses WHERE status_name = 'Прибыло в город назначения'), now() - interval '1 day');


INSERT INTO app.parcel_movements (parcel_id, segment_id, employee_id, status_id, event_timestamp) VALUES
(5, 8, 6, (SELECT id FROM ref.parcel_statuses WHERE status_name = 'Зарегистрировано'), now() - interval '4 days'),
(5, 8, 6, (SELECT id FROM ref.parcel_statuses WHERE status_name = 'Принято в отделении отправки'), now() - interval '4 days'),
(5, 9, 5, (SELECT id FROM ref.parcel_statuses WHERE status_name = 'В пути'), now() - interval '2 days'),
(5, 10, 10, (SELECT id FROM ref.parcel_statuses WHERE status_name = 'Прибыло в город назначения'), now() - interval '1 day');


GRANT CREATE ON SCHEMA audit TO auditor;
SET ROLE auditor;

CREATE TABLE audit.login_log (
    log_id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    login_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    session_user_name TEXT NOT NULL,
    current_user_name TEXT NOT NULL,
    client_ip INET
);
COMMENT ON TABLE audit.login_log IS 'Журнал входов пользователей в систему';


CREATE OR REPLACE FUNCTION audit.log_user_connection()
RETURNS event_trigger AS $$
BEGIN
    INSERT INTO audit.login_log (session_user_name, current_user_name, client_ip)
    VALUES (session_user, current_user, inet_client_addr()); 
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

RESET ROLE;

CREATE EVENT TRIGGER login_trigger ON login
  EXECUTE FUNCTION audit.log_user_connection();

REVOKE ALL ON audit.login_log FROM PUBLIC;
GRANT EXECUTE ON FUNCTION audit.log_user_connection() TO app_reader, app_writer, ddl_admin, dml_admin, security_admin;


















-- Сообщаем об успешном завершении скрипта
SELECT 'Initial setup script completed successfully' AS status;