CREATE DATABASE IF NOT EXISTS cyberforce;

DROP TABLE IF EXISTS cyberforce.supersecret;
CREATE TABLE cyberforce.supersecret (
    data INT NOT NULL
);
INSERT INTO cyberforce.supersecret (data) VALUES (7);

DROP USER IF EXISTS 'scoring-sql'@'%';
CREATE USER 'scoring-sql'@'%' IDENTIFIED BY 'password';
GRANT SELECT ON cyberforce.supersecret TO 'scoring-sql'@'%';
FLUSH PRIVILEGES;
