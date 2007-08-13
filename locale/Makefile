#
# Makefile
#
# $Id$

### Targets:
PREPARE = de.po \
#      fr.po \
#      it.po ne.po po.po \
#      su.po es.po

TRANSLATION = de.mo \
#      fr.mo \
#      it.mo ne.mo po.mo \
#      su.mo es.mo

MODULES = ../lib/XXV/MODULES/AUTOTIMER.pm \
  ../lib/XXV/MODULES/CHANNELS.pm \
  ../lib/XXV/MODULES/CHRONICLE.pm \
  ../lib/XXV/MODULES/CONFIG.pm \
  ../lib/XXV/MODULES/EPG.pm \
  ../lib/XXV/MODULES/EVENTS.pm \
  ../lib/XXV/MODULES/GRAB.pm \
  ../lib/XXV/MODULES/HTTPD.pm \
  ../lib/XXV/MODULES/INTERFACE.pm \
  ../lib/XXV/MODULES/LOGREAD.pm \
  ../lib/XXV/MODULES/MEDIALIB.pm \
  ../lib/XXV/MODULES/MUSIC.pm \
  ../lib/XXV/MODULES/RECORDS.pm \
  ../lib/XXV/MODULES/REMOTE.pm \
  ../lib/XXV/MODULES/REPORT.pm \
  ../lib/XXV/MODULES/ROBOT.pm \
  ../lib/XXV/MODULES/SHARE.pm \
  ../lib/XXV/MODULES/STATUS.pm \
  ../lib/XXV/MODULES/STREAM.pm \
  ../lib/XXV/MODULES/SVDRP.pm \
  ../lib/XXV/MODULES/TELNET.pm \
  ../lib/XXV/MODULES/TIMERS.pm \
  ../lib/XXV/MODULES/USER.pm \
  ../lib/XXV/MODULES/VTX.pm \
  ../lib/XXV/MODULES/WAPD.pm \
  ../lib/XXV/OUTPUT/Ajax.pm \
  ../lib/XXV/OUTPUT/Console.pm \
  ../lib/XXV/OUTPUT/Dump.pm \
  ../lib/XXV/OUTPUT/Html.pm \
  ../lib/XXV/OUTPUT/Wml.pm \
  ../lib/XXV/OUTPUT/HTML/PUSH.pm \
  ../lib/XXV/OUTPUT/HTML/WAIT.pm \
  ../lib/XXV/OUTPUT/NEWS/JABBER.pm \
  ../lib/XXV/OUTPUT/NEWS/MAIL.pm \
  ../lib/XXV/OUTPUT/NEWS/RSS.pm \
  ../lib/XXV/OUTPUT/NEWS/VDR.pm \
  ../bin/xxvd \
  ../html/*.tmpl \
  ../html/widgets/*.tmpl \
  ../html/javascript/*.js \
  ../wml/*.tmpl \
  ../wml/widgets/*.tmpl


### TODO Need Touch if only a Modul is changed
# Dependencies:
DEPFILE = .dependencies
$(DEPFILE): Makefile
	@echo $(MODULES) : $(PREPARE) > $@

-include $(DEPFILE)

### Merge all gettext-entry on Modules with language.po files
%.po: $(DEPFILE)
	@-cp -f "$@" "$@~" > /dev/null
	@mkdir -p xxv
	@for i in $(MODULES) ; \
        do SUBDIR=$$(echo `dirname "$$i"` | sed -e "s/\.\.\///g;") ; \
        mkdir -p xxv/$$SUBDIR ; \
        cat "$$i" | tr -d '\r' > xxv/$$SUBDIR/`basename "$$i"`; \
        done
	@mkdir -p xxv/locale
	@cd xxv/locale && \
          ../../xgettext.pl -o ../../"$@" `find .. -type f`
	@-rm -rf xxv

### Convert language.po to GNU message catalog language.mo
%.mo: %.po
	@-mkdir -p $*/LC_MESSAGES
	@msgfmt -f  $< -o $*/LC_MESSAGES/xxv.mo


#### Rules

prepare: $(PREPARE)

all: $(TRANSLATION)

clean:
	@-rm -f *~ $(DEPFILE)

export:	clean
	@tar czf ../locale.tgz -C .. locale
