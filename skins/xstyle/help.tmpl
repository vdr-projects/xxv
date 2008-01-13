<script type="text/javascript">

webfxMenuImagePath = "images/"


webfxMenuUseHover = true;
webfxMenuHideTime = 500;
webfxMenuShowTime = 200;

var myBar = new WebFXMenuBar;


<?% IF allow('now') %?>
        var runnow = new WebFXMenu;
        var runnowGrp = new WebFXMenu;
    <?% FOREACH group = getModule('CHANNELS').ChannelGroupsArray('Name') %?>
        runnowGrp.add(new WebFXMenuItem('<?% group.first %?>',  "?cmd=now&data=&__cgrp=<?% group.last %?>"));
    <?% END %?>
        runnow.add(new WebFXMenuItem("<?% gettext("Running now",12) %?>",null,null,runnowGrp));

        var runnextGrp = new WebFXMenu;
    <?% FOREACH group = getModule('CHANNELS').ChannelGroupsArray('Name') %?>
        runnextGrp.add(new WebFXMenuItem('<?% group.first %?>',  "?cmd=next&data=&__cgrp=<?% group.last %?>"));
    <?% END %?>
        runnow.add(new WebFXMenuItem("<?% gettext("Next",12) %?>",null,null,runnextGrp));
        runnow.add(new WebFXMenuSeparator());

    <?% USE date %?>
    <?% periods = getModule('EPG').periods %?>
    <?% FOREACH zeit = periods.split(','); %?>
        <?% runningnext = 0 %?>
        <?% tom = 0 %?>
        <?% PERL %?>
            use Date::Manip;
            my $z;
            $z   = UnixDate(ParseDate($stash->{zeit}),"%s") || 0;
            if($z and $z < time) {
                $z += 86400;
                $stash->set('tom', 1);
            }
            $stash->set('z', $z);
        <?% END %?>
        <?% NEXT UNLESS z %?>

        <?% IF tom %?>
        runnow.add(new WebFXMenuItem("<?% date.format(z, "%H:%M (%a)", locale) %?>",  "?cmd=now&amp;data=<?% z %?>&amp;__cgrp=<?% cgi.param('__cgrp') %?>"));
        <?% ELSE %?>
        runnow.add(new WebFXMenuItem("<?% date.format(z, "%H:%M", locale) %?>",  "?cmd=now&amp;data=<?% z %?>&amp;__cgrp=<?% cgi.param('__cgrp') %?>"));
        <?% END %?>
    <?% END %?>
    myBar.add(new WebFXMenuButton("<?% gettext("Running now") %?>",null,null,runnow));
<?% END %?>


// -----

<?% IF allow('schema') %?>
    var program = new WebFXMenu;
    program.add(new WebFXMenuItem("<?% gettext("Schema") %?>",  "?cmd=schema"));
    <?% IF allow('topten') %?>program.add(new WebFXMenuItem("<?% gettext("Top ten entry") %?>",  "?cmd=t10"));<?% END %?>
    program.add(new WebFXMenuItem("<?% gettext("Search") %?>",  "?cmd=search"));
    program.add(new WebFXMenuSeparator());
    <?% FOREACH group = getModule('CHANNELS').ChannelGroupsArray('Name') %?>
            var programGrp<?% group.last %?> = new WebFXMenu;
        <?% z = 0 %?>
        <?% FOREACH ch = getModule('CHANNELS').ChannelArray('Name', "GRP = ${group.last}") %?>
            <?% z = z + 1 %?>
            <?% LAST IF z > global.cfgMaxChannelMenuEntrys %?>
            programGrp<?% group.last %?>.add(new WebFXMenuItem('<?% escape(ch.first) %?>',  '?cmd=program&data=<?% ch.last %?>'));
        <?% END %?>
            program.add(new WebFXMenuItem('<?% group.first %?>',null,null,programGrp<?% group.last %?>));
    <?% END %?>

    <?% IF allow('erestart') %?>
      program.add(new WebFXMenuSeparator());
      program.add(new WebFXMenuItem("<?% gettext("Update EPG data",12) %?>","?cmd=erestart"));
    <?% END %?>

    myBar.add(new WebFXMenuButton("<?% gettext("Program guide") %?>",null,null,program));
<?% END %?>

// -----
    var control = new WebFXMenu;
    <?% IF allow('alist') %?>control.add(new WebFXMenuItem("<?% gettext("Autotimer",12) %?>",     "?cmd=alist"));<?% END %?>
    <?% IF allow('tlist') %?>control.add(new WebFXMenuItem("<?% gettext("Timers",12) %?>",        "?cmd=tlist"));<?% END %?>
    <?% IF allow('movetimerlist') %?>control.add(new WebFXMenuItem("<?% gettext("Rules to move timer",12) %?>","?cmd=movetimerlist"));<?% END %?>
    myBar.add(new WebFXMenuButton("<?% gettext("Programming") %?>",null,null,control));

    var media = new WebFXMenu;
    <?% IF allow('rlist') %?>media.add(new WebFXMenuItem("<?% gettext("Recordings",12) %?>",    "?cmd=rlist"));<?% END %?>
    <?% IF allow('mlist') %?>media.add(new WebFXMenuItem("<?% gettext("Music",12) %?>",         "?cmd=mlist"));<?% END %?>
    <?% IF allow('mllist') %?>media.add(new WebFXMenuItem("<?% gettext("Media library",12) %?>","?cmd=mllist"));<?% END %?>
    myBar.add(new WebFXMenuButton("<?% gettext("Media content") %?>",null,null,media));


    var tools = new WebFXMenu;
    <?% IF allow('remote') %?>tools.add(new WebFXMenuItem("<?% gettext("Remote",12) %?>",        "?cmd=remote"));<?% END %?>
    <?% IF allow('vtxpage') %?>tools.add(new WebFXMenuItem("<?% gettext("Teletext",12) %?>",     "?cmd=vtxpage"));<?% END %?>
    <?% IF allow('cmdlist') %?>tools.add(new WebFXMenuItem("<?% gettext("Commands",12) %?>",     "?cmd=cmdlist"));<?% END %?>
    <?% IF allow('report') %?>tools.add(new WebFXMenuItem("<?% gettext("Report",12) %?>","?cmd=report"));<?% END %?>

    myBar.add(new WebFXMenuButton("<?% gettext("Tools") %?>",null,null,tools));

// -----

    var admin = new WebFXMenu;
    <?% IF allow('cl') %?>admin.add(new WebFXMenuItem("<?% gettext("Channels",12) %?>",  "?cmd=cl"));<?% END %?>
    <?% IF allow('ul') %?>admin.add(new WebFXMenuItem("<?% gettext("User",12) %?>","?cmd=ul"));
    <?% ELSIF allow('uprefs') %?>admin.add(new WebFXMenuItem("<?% gettext("Personality",12) %?>","?cmd=uprefs"));<?% END %?>
    <?% IF allow('rel') %?>admin.add(new WebFXMenuItem("<?% gettext("Reload",12) %?>","?cmd=rel"));<?% END %?>
    <?% IF allow('logout') %?>admin.add(new WebFXMenuItem("<?% gettext("Logout",12) %?>","?cmd=logout"));<?% END %?>
    <?% IF allow('restart') %?>admin.add(new WebFXMenuItem("<?% gettext("Restart",12) %?>","?cmd=restart"));<?% END %?>

    myBar.add(new WebFXMenuButton("<?% gettext("Administration") %?>",null,null,admin));

// -----

<?% IF allow('configedit') %?>
    var prefs = new WebFXMenu;
    <?% FOREACH co = getModule('CONFIG').realModNames %?>
      <?% IF co != "CONFIG" %?>
        prefs.add(new WebFXMenuItem("<?% chop(co,12) %?>",  "?cmd=configedit&amp;data=<?% co %?>"));
      <?% END %?>
    <?% END %?>
    myBar.add(new WebFXMenuButton("<?% gettext("Preferences") %?>",null,null,prefs));
<?% END %?>

// -----

<?% IF allow('sa') %?>
    var status = new WebFXMenu;
    status.add(new WebFXMenuItem("<?% gettext("Status") %?>",      "?cmd=sa"));
    status.add(new WebFXMenuSeparator());
    status.add(new WebFXMenuItem("<?% gettext("Vitals") %?>",      "?cmd=sv"));
    status.add(new WebFXMenuItem("<?% gettext("Memory") %?>",      "?cmd=sm"));
    status.add(new WebFXMenuItem("<?% gettext("Filesystem") %?>",  "?cmd=sf"));
    status.add(new WebFXMenuItem("<?% gettext("Network") %?>",     "?cmd=sn"));
    status.add(new WebFXMenuItem("<?% gettext("Hardware") %?>",    "?cmd=sh"));
    <?% IF allow('logger') %?>
    var logger = new WebFXMenu;
    logger.add(new WebFXMenuItem("<?% gettext("Standard") %?>",  "?cmd=logger&data=main"));
    logger.add(new WebFXMenuItem("<?% gettext("Syslog") %?>",    "?cmd=logger&data=syslog"));
    status.add(new WebFXMenuItem("<?% gettext("Log files") %?>",null,null,logger));
    <?% END %?>
    myBar.add(new WebFXMenuButton("<?% gettext("Status") %?>",null,null,status));
<?% END %?>

// -----

<?% IF allow('more') %?>
    var info = new WebFXMenu;
    info.add(new WebFXMenuItem("<?% gettext("News") %?>",   "?cmd=more&data=NEWS"));
    info.add(new WebFXMenuItem("<?% gettext("History") %?>",   "?cmd=more&data=CHANGELOG"));
    info.add(new WebFXMenuItem("<?% gettext("License") %?>",   "?cmd=more&data=COPYING"));
    info.add(new WebFXMenuItem("<?% gettext("Readme") %?>",   "?cmd=more&data=<?% gettext('Readme') FILTER upper %?>"));
    info.add(new WebFXMenuItem("<?% gettext("Tutorial") %?>",   "?cmd=more&data=TUTORIAL"));
    myBar.add(new WebFXMenuButton("<?% gettext("Documentation") %?>",null,null,info));
<?% END %?>

document.write(myBar);

</script>
