-- MySQL dump 10.11
--
-- Host: localhost    Database: xxv
-- ------------------------------------------------------
-- Server version	5.0.32-Debian_7etch1
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO,MYSQL40,NO_TABLE_OPTIONS' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `AUTOTIMER`
--

DROP TABLE IF EXISTS `AUTOTIMER`;
CREATE TABLE `AUTOTIMER` (
  `Id` int(11) unsigned NOT NULL auto_increment,
  `Activ` enum('y','n') default 'y',
  `Done` set('timer','recording','chronicle') NOT NULL default 'timer',
  `Search` text NOT NULL,
  `InFields` set('title','subtitle','description') NOT NULL,
  `Channels` text,
  `Start` char(4) default '0000',
  `Stop` char(4) default '0000',
  `MinLength` tinyint(4) default NULL,
  `Priority` tinyint(2) default NULL,
  `Lifetime` tinyint(2) default NULL,
  `Dir` text,
  `VPS` enum('y','n') default 'n',
  `prevminutes` tinyint(4) default NULL,
  `afterminutes` tinyint(4) default NULL,
  `Weekdays` set('Mon','Tue','Wed','Thu','Fri','Sat','Sun') default NULL,
  `startdate` datetime default NULL,
  `stopdate` datetime default NULL,
  `count` int(11) default NULL,
  PRIMARY KEY  (`Id`)
);

--
-- Table structure for table `CHRONICLE`
--

DROP TABLE IF EXISTS `CHRONICLE`;
CREATE TABLE `CHRONICLE` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `hash` varchar(16) NOT NULL default '',
  `title` text NOT NULL,
  `channel_id` varchar(100) NOT NULL default '',
  `starttime` datetime NOT NULL default '0000-00-00 00:00:00',
  `duration` int(11) NOT NULL default '0',
  PRIMARY KEY  (`id`),
  UNIQUE KEY `hash` (`hash`)
);

--
-- Table structure for table `MEDIALIB_ACTORS`
--

DROP TABLE IF EXISTS `MEDIALIB_ACTORS`;
CREATE TABLE `MEDIALIB_ACTORS` (
  `name` varchar(255) NOT NULL default '',
  `actorid` varchar(15) NOT NULL default '',
  `imgurl` varchar(255) NOT NULL default '',
  `checked` timestamp NOT NULL,
  PRIMARY KEY  (`name`)
);

--
-- Table structure for table `MEDIALIB_VIDEODATA`
--

DROP TABLE IF EXISTS `MEDIALIB_VIDEODATA`;
CREATE TABLE `MEDIALIB_VIDEODATA` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `md5` varchar(32) default NULL,
  `title` varchar(255) default NULL,
  `subtitle` varchar(255) default NULL,
  `language` varchar(255) default NULL,
  `diskid` varchar(15) default NULL,
  `comment` varchar(255) default NULL,
  `disklabel` varchar(32) default NULL,
  `imdbID` varchar(15) default NULL,
  `year` year(4) default NULL,
  `imgurl` varchar(255) default NULL,
  `director` varchar(255) default NULL,
  `actors` text,
  `runtime` int(10) unsigned default NULL,
  `country` varchar(255) default NULL,
  `plot` text,
  `filename` varchar(255) default NULL,
  `filesize` int(16) unsigned default NULL,
  `filedate` datetime default NULL,
  `audio_codec` varchar(255) default NULL,
  `video_codec` varchar(255) default NULL,
  `video_width` int(10) unsigned default NULL,
  `video_height` int(10) unsigned default NULL,
  `istv` tinyint(1) unsigned NOT NULL default '0',
  `lastupdate` timestamp NOT NULL,
  `seen` tinyint(1) unsigned NOT NULL default '0',
  `mediatype` int(10) unsigned NOT NULL default '0',
  `custom1` varchar(255) default NULL,
  `custom2` varchar(255) default NULL,
  `custom3` varchar(255) default NULL,
  `custom4` varchar(255) default NULL,
  `created` datetime default NULL,
  `owner_id` int(11) NOT NULL default '0',
  PRIMARY KEY  (`id`),
  KEY `seen` (`seen`),
  KEY `title_idx` (`title`),
  KEY `diskid_idx` (`diskid`),
  KEY `mediatype` (`mediatype`,`istv`),
  FULLTEXT KEY `actors_idx` (`actors`),
  FULLTEXT KEY `comment` (`comment`)
);

--
-- Table structure for table `MEDIALIB_VIDEOGENRE`
--

DROP TABLE IF EXISTS `MEDIALIB_VIDEOGENRE`;
CREATE TABLE `MEDIALIB_VIDEOGENRE` (
  `video_id` int(10) unsigned NOT NULL default '0',
  `genre_id` int(10) unsigned NOT NULL default '0',
  PRIMARY KEY  (`video_id`,`genre_id`)
);

--
-- Table structure for table `USER`
--

DROP TABLE IF EXISTS `USER`;
CREATE TABLE `USER` (
  `Id` int(11) unsigned NOT NULL auto_increment,
  `Name` varchar(100) NOT NULL default '',
  `Password` varchar(100) NOT NULL,
  `Level` set('admin','user','guest') NOT NULL,
  `Prefs` varchar(100) default '',
  `UserPrefs` varchar(100) default '',
  `Deny` set('tlist','alist','rlist','mlist','tedit','aedit','redit','remote','stream','cedit','media') default NULL,
  `MaxLifeTime` tinyint(2) default '0',
  `MaxPriority` tinyint(2) default '0',
  PRIMARY KEY  (`Id`)
);
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2007-11-24 14:27:24
