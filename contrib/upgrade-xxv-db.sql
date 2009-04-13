-- MySQL dump 10.11
--
-- Host: localhost    Database: xxv
-- ------------------------------------------------------
-- Server version	5.0.51a-24
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `AUTOTIMER`
--

SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE IF NOT EXISTS `AUTOTIMER` (
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
  `keywords` text,
  PRIMARY KEY  (`Id`)
);
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `CHRONICLE`
--

SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE IF NOT EXISTS `CHRONICLE` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `hash` varchar(16) NOT NULL default '',
  `title` text NOT NULL,
  `channel_id` varchar(100) NOT NULL default '',
  `starttime` datetime NOT NULL default '0000-00-00 00:00:00',
  `duration` int(11) NOT NULL default '0',
  PRIMARY KEY  (`id`),
  UNIQUE KEY `hash` (`hash`)
);
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `MEDIALIB_ACTORS`
--

SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE IF NOT EXISTS `MEDIALIB_ACTORS` (
  `name` varchar(255) NOT NULL default '',
  `actorid` varchar(15) NOT NULL default '',
  `imgurl` varchar(255) NOT NULL default '',
  `checked` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`name`)
);
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `MEDIALIB_VIDEODATA`
--

SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE IF NOT EXISTS `MEDIALIB_VIDEODATA` (
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
  `lastupdate` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
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
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `MEDIALIB_VIDEOGENRE`
--

SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE IF NOT EXISTS `MEDIALIB_VIDEOGENRE` (
  `video_id` int(10) unsigned NOT NULL default '0',
  `genre_id` int(10) unsigned NOT NULL default '0',
  PRIMARY KEY  (`video_id`,`genre_id`)
);
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `MOVETIMER`
--

SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE IF NOT EXISTS `MOVETIMER` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `sourcevid` int(10) unsigned NOT NULL default '1',
  `source` varchar(64) NOT NULL,
  `destinationvid` int(10) unsigned NOT NULL default '1',
  `destination` varchar(64) NOT NULL,
  `move` enum('y','n','collision') default 'collision',
  `original` enum('move','keep','copy') default 'move',
  PRIMARY KEY  (`id`),
  UNIQUE KEY `sourcevid` (`sourcevid`,`source`)
);
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `USER`
--

SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE IF NOT EXISTS `USER` (
  `Id` int(11) unsigned NOT NULL auto_increment,
  `Name` varchar(100) NOT NULL default '',
  `Password` varchar(32) NOT NULL,
  `Level` set('admin','user','guest') NOT NULL,
  `Prefs` text,
  `UserPrefs` text,
  `Deny` set('tlist','alist','rlist','mlist','tedit','aedit','redit','remote','stream','cedit','media') default NULL,
  `MaxLifeTime` tinyint(2) default '0',
  `MaxPriority` tinyint(2) default '0',
  PRIMARY KEY  (`Id`)
);
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `XMLTV`
--

SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE IF NOT EXISTS `XMLTV` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `active` enum('y','n') default 'n',
  `xmltvname` varchar(256) NOT NULL,
  `vid` int(10) unsigned NOT NULL default '1',
  `channel` varchar(64) NOT NULL,
  `template` enum('y','n') default 'n',
  `updateinterval` enum('e','d','w') default 'e',
  `source` text NOT NULL,
  `updated` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`id`),
  UNIQUE KEY `vid` (`vid`,`channel`)
);
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `RECORDER`
--

SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE IF NOT EXISTS `RECORDER` (
  `id` int(11) unsigned NOT NULL auto_increment,
  `active` enum('y','n') default 'y',
  `master` enum('y','n') default 'n',
  `host` varchar(100) NOT NULL default 'localhost',
  `port` smallint(4) unsigned default '2001',
  `cards` varchar(100) default '',
  `videodirectory` text,
  PRIMARY KEY  (`id`)
);
SET character_set_client = @saved_cs_client;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2009-04-13  9:58:19
