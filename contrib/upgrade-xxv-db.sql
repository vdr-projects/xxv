-- MySQL dump 10.10
--
-- Host: localhost    Database: xxv
-- ------------------------------------------------------
-- Server version	5.0.30-Debian_3

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
) TYPE=MyISAM;

--
-- Table structure for table `CHANNELGROUPS`
--

DROP TABLE IF EXISTS `CHANNELGROUPS`;
CREATE TABLE `CHANNELGROUPS` (
  `Id` int(11) NOT NULL auto_increment,
  `Name` varchar(100) default 'unknown',
  `Counter` int(11) default '0',
  PRIMARY KEY  (`Id`)
) TYPE=MyISAM;

--
-- Table structure for table `CHANNELS`
--

DROP TABLE IF EXISTS `CHANNELS`;
CREATE TABLE `CHANNELS` (
  `Id` varchar(100) NOT NULL,
  `Name` varchar(100) NOT NULL default '',
  `Frequency` int(11) NOT NULL default '0',
  `Parameters` varchar(100) default '',
  `Source` varchar(100) default NULL,
  `Srate` int(11) default '0',
  `VPID` varchar(100) default '',
  `APID` varchar(100) default '',
  `TPID` varchar(100) default '',
  `CA` varchar(100) default '',
  `SID` int(11) default '0',
  `NID` int(11) default '0',
  `TID` int(11) default '0',
  `RID` int(11) default '0',
  `GRP` int(11) default '0',
  `POS` int(11) NOT NULL,
  PRIMARY KEY  (`Id`)
) TYPE=MyISAM;

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
) TYPE=MyISAM;

--
-- Table structure for table `EPG`
--

DROP TABLE IF EXISTS `EPG`;
CREATE TABLE `EPG` (
  `eventid` bigint(20) unsigned NOT NULL default '0',
  `title` text NOT NULL,
  `subtitle` text,
  `description` text,
  `channel_id` varchar(100) NOT NULL default '',
  `starttime` datetime NOT NULL default '0000-00-00 00:00:00',
  `duration` int(11) NOT NULL default '0',
  `tableid` tinyint(4) default '0',
  `image` text,
  `version` tinyint(3) default '0',
  `video` varchar(100) default '',
  `audio` varchar(255) default '',
  `addtime` datetime NOT NULL default '0000-00-00 00:00:00',
  `vpstime` datetime default '0000-00-00 00:00:00',
  PRIMARY KEY  (`eventid`),
  KEY `starttime` (`starttime`),
  KEY `channel_id` (`channel_id`)
) TYPE=MyISAM;

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
) TYPE=MyISAM;

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
) TYPE=MyISAM;

--
-- Table structure for table `MEDIALIB_VIDEOGENRE`
--

DROP TABLE IF EXISTS `MEDIALIB_VIDEOGENRE`;
CREATE TABLE `MEDIALIB_VIDEOGENRE` (
  `video_id` int(10) unsigned NOT NULL default '0',
  `genre_id` int(10) unsigned NOT NULL default '0',
  PRIMARY KEY  (`video_id`,`genre_id`)
) TYPE=MyISAM;

--
-- Table structure for table `MUSIC`
--

DROP TABLE IF EXISTS `MUSIC`;
CREATE TABLE `MUSIC` (
  `Id` int(11) unsigned NOT NULL auto_increment,
  `FILE` text NOT NULL,
  `ARTIST` varchar(128) default 'unknown',
  `ALBUM` varchar(128) default 'unknown',
  `TITLE` varchar(128) default 'unknown',
  `COMMENT` varchar(128) default NULL,
  `TRACKNUM` varchar(10) default '0',
  `YEAR` smallint(4) unsigned default NULL,
  `GENRE` varchar(128) default NULL,
  `BITRATE` smallint(4) unsigned default NULL,
  `FREQUENCY` varchar(4) default NULL,
  `SECS` int(11) NOT NULL,
  PRIMARY KEY  (`Id`)
) TYPE=MyISAM;

--
-- Table structure for table `OLDEPG`
--

DROP TABLE IF EXISTS `OLDEPG`;
CREATE TABLE `OLDEPG` (
  `eventid` bigint(20) unsigned NOT NULL default '0',
  `title` text NOT NULL,
  `subtitle` text,
  `description` text,
  `channel_id` varchar(100) NOT NULL default '',
  `starttime` datetime NOT NULL default '0000-00-00 00:00:00',
  `duration` int(11) NOT NULL default '0',
  `tableid` tinyint(4) default '0',
  `image` text,
  `version` tinyint(3) default '0',
  `video` varchar(100) default '',
  `audio` varchar(255) default '',
  `addtime` datetime NOT NULL default '0000-00-00 00:00:00',
  `vpstime` datetime default '0000-00-00 00:00:00',
  PRIMARY KEY  (`eventid`),
  KEY `starttime` (`starttime`),
  KEY `channel_id` (`channel_id`)
) TYPE=MyISAM;

--
-- Table structure for table `RECORDS`
--

DROP TABLE IF EXISTS `RECORDS`;
CREATE TABLE `RECORDS` (
  `eventid` bigint(20) unsigned NOT NULL,
  `RecordId` int(11) unsigned NOT NULL,
  `RecordMD5` varchar(32) NOT NULL,
  `Path` text NOT NULL,
  `Prio` tinyint(4) NOT NULL,
  `Lifetime` tinyint(4) NOT NULL,
  `State` tinyint(4) NOT NULL,
  `FileSize` int(11) unsigned default '0',
  `Marks` text,
  `Type` enum('TV','RADIO','UNKNOWN') default 'TV',
  `addtime` timestamp NOT NULL,
  PRIMARY KEY  (`eventid`),
  UNIQUE KEY `eventid` (`eventid`)
) TYPE=MyISAM;

--
-- Table structure for table `TIMERS`
--

DROP TABLE IF EXISTS `TIMERS`;
CREATE TABLE `TIMERS` (
  `Id` int(11) unsigned NOT NULL,
  `Status` char(1) default '1',
  `ChannelID` varchar(100) NOT NULL default '',
  `Day` varchar(20) default '-------',
  `Start` int(11) unsigned default NULL,
  `Stop` int(11) unsigned default NULL,
  `Priority` tinyint(2) default NULL,
  `Lifetime` tinyint(2) default NULL,
  `File` text,
  `Summary` text,
  `NextStartTime` datetime default NULL,
  `NextStopTime` datetime default NULL,
  `Collision` varchar(100) default '0',
  `eventid` bigint(20) unsigned default '0',
  `eventstarttime` datetime default NULL,
  `eventduration` int(10) unsigned default '0',
  `AutotimerId` int(11) unsigned default '0',
  `addtime` timestamp NOT NULL,
  `Checked` char(1) default '0',
  PRIMARY KEY  (`Id`)
) TYPE=MyISAM;

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
) TYPE=MyISAM;

--
-- Table structure for table `VERSION`
--

DROP TABLE IF EXISTS `VERSION`;
CREATE TABLE `VERSION` (
  `Version` tinyint(4) NOT NULL default '0'
) TYPE=MyISAM;
