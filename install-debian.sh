#!/bin/bash
#
# MiniInstall for xxv
#
# Usage: xxv

XXVSOURCE=`pwd`

lastchar()
{
    # return the last character of a string in $rval
    if [ -z "$1" ]; then
        # empty string
        rval=""
        return
    fi
    # wc puts some space behind the output this is why we need sed:
    numofchar=`echo -n "$1" | wc -c | sed 's/ //g' `
    # now cut out the last char
    rval=`echo -n "$1" | cut -b $numofchar`
}

echo 'Install Manpage'
cp doc/xxvd.1 /usr/share/man/man1

echo 'Logrotate'
cp etc/logrotate.d/xxvd /etc/logrotate.d/xxvd

if [ ! -e /usr/bin/vdr2jpeg ] ; then
  echo 'install vdr2jpeg'
  apt-get install vdr2jpeg
fi

echo 'install PerlModules'
apt-get install libdbi-perl \
                libevent-perl \
                libgd-gd2-noxpm-perl \
                libgd-graph-perl \
                libgd-graph3d-perl \
                libgd-text-perl \
                libhtml-parser-perl \
                libhtml-tagset-perl \
                libhtml-template-perl \
                libhtml-tree-perl \
                liblocale-gettext-perl \
                libnet-telnet-perl \
                libterm-readkey-perl \
                liburi-perl \
                libwww-perl \
                liblog-log4perl-perl \
                libxml-simple-perl \
                libproc-process-perl \
                libio-zlib-perl \
                libnet-xmpp-perl \
                libterm-readline-gnu-perl \
		            libxml-rss-perl \
            		libsoap-lite-perl \
                libnet-amazon-perl \
                libjson-perl \
                libnet-telnet-perl

echo 'start mysql server'
/etc/init.d/mysql start

echo 'create Database'
cat contrib/create-database.sql | mysql -u root

echo 'DB connectstring write in config'
echo '[General]' >> ~/.xxvd.cfg
echo 'DSN=DBI:mysql:database=xxv;host=localhost;port=3306' >> ~/.xxvd.cfg
echo 'PWD=xxv' >> ~/.xxvd.cfg
echo 'USR=xxv' >> ~/.xxvd.cfg

echo 'create Startscript'
sed -e 's/FOLDER=\".+?\"/FOLDER=\"$XXVSOURCE\"/' etc/xxvd > /etc/init.d/xxvd
chmod 775 /etc/init.d/xxvd
RVV=`runlevel`
lastchar "$RVV"
ln -s /etc/init.d/xxvd "/etc/rc$rval.d/S90xxvd"

echo 'Start XXV'
/etc/init.d/xxvd restart

echo 'read the Logfile'
tail -f /var/log/xxvd.log

echo 'Now you can call a browser to address:'
echo 'http://your_vdr:8080/'
echo 'have Fun'


