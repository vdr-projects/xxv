#!/bin/sh
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

apt-get install \
  perl \
  perl-base \
  perl-modules \
  libcgi-perl \
  libio-zlib-perl \
  libconfig-tiny-perl \
  libdate-manip-perl \
  libdbd-mysql-perl \
  libdbi-perl \
  libmd5-perl \
  libdigest-hmac-perl \
  libevent-perl \
  libgd-gd2-noxpm-perl libgd-graph-perl libgd-graph3d-perl libgd-text-perl \
  txt2html \
  libhtml-tree-perl \
  libjson-perl 
  libwww-perl \
  liblocale-gettext-perl \
  libmp3-info-perl \
  libnet-amazon-perl \
  libnet-telnet-perl \
  libnet-xmpp-perl \
  libproc-process-perl \
  libsoap-lite-perl \
  libtemplate-perl \
  libhtml-template-perl \
  liburi-perl \
  libxml-rss-perl \
  libxml-simple-perl

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


