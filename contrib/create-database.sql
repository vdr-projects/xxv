--
-- Current Database: mysql
--
use mysql;

CREATE DATABASE IF NOT EXISTS xxv;

use xxv;

-- Create a mysql-Account : Adjust User and Password here and add this to xxvd.cfg 
-- [General]
-- DSN=DBI:mysql:database=xxv;host=localhost;port=3306
-- PWD=password
-- USR=username

-- The first line is useful for granting access to user xxv on all computers in a network.
-- grant all privileges on xxv.* to username@'%' IDENTIFIED BY 'password'; --

-- Grant access to user xxv on the local machine with password 'xxv'
grant all privileges on xxv.* to xxv@localhost IDENTIFIED BY 'xxv';

flush privileges;
