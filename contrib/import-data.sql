--
-- Load files to Database xxv
--

DELETE from AUTOTIMER;
DELETE from CHRONICLE;
DELETE from USER;
DELETE from MEDIALIB_ACTORS;
DELETE from MEDIALIB_VIDEODATA;
DELETE from MEDIALIB_VIDEOGENRE;

load data infile '/tmp/autotimer.sav' into table AUTOTIMER;
load data infile '/tmp/user.sav' into table USER;
load data infile '/tmp/chronicle.sav' into table CHRONICLE;
load data infile '/tmp/medialib_actors.sav' into table MEDIALIB_ACTORS;
load data infile '/tmp/medialib_videodata.sav' into table MEDIALIB_VIDEODATA;
load data infile '/tmp/medialib_videogenre.sav' into table MEDIALIB_VIDEOGENRE;
