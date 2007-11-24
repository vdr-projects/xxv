#
# Makefile
#
# $Id$

XXV = xxv
VERSION = 1.0.1

### The name of the distribution archive:

ARCHIVE = $(XXV)-$(VERSION)
PACKAGE = $(ARCHIVE)
TMPDIR = /tmp

### The subdirectories:

### Targets:
INCLUDE = bin contrib doc etc html share lib locale wml README INSTALL Makefile install.sh
EXCLUDE = "*~" "*.bak" "*.org" "*.diff" "xxvd.pid" "$(XXV)-*.tgz"


clean:
	@for i in $(EXCLUDE) ;\
	do \
	    find -name "$$i" -exec rm -rf "{}" \; \
	|| exit 1;\
	done

tmpfolder:
	@-rm -rf $(TMPDIR)/$(ARCHIVE)
	@mkdir -p $(TMPDIR)/$(ARCHIVE)

copyfiles:
	@for i in $(INCLUDE) ;\
	do \
	    cp -a $$i $(TMPDIR)/$(ARCHIVE) \
	|| exit 1;\
	done

removefiles:
	@for i in $(EXCLUDE) ;\
	do \
	    find $(TMPDIR)/$(ARCHIVE) -name "$$i" -exec rm -f "{}" \; \
	|| exit 1;\
	done
	@for i in $(EXCLUDEFOLDER) ;\
	do \
	    find "$(TMPDIR)/$(ARCHIVE)/$$i" -exec rm -rf "{}" \; \
	|| exit 1;\
	done

updateversion:
	@sed -e "s/__VERSION__/$(VERSION)/g" bin/xxvd > $(TMPDIR)/$(ARCHIVE)/bin/xxvd

DBTABLES = $(shell cat ./contrib/update-xxv | grep tables= | cut -d '=' -f 2 | sed -e s/\'//g;)
updatesql:
	@echo Please type the DB-Password for root:
	@mysqldump -p -n -d --add-drop-table --compatible=mysql40,no_table_options -p -u root xxv $(DBTABLES) VERSION -r ./contrib/upgrade-xxv-db.sql

setpermission:
	@find $(TMPDIR)/$(ARCHIVE) -type d -exec chmod 755 {} \;
	@find $(TMPDIR)/$(ARCHIVE) -type f -exec chmod 644 {} \;
	@chmod a+x $(TMPDIR)/$(ARCHIVE)/bin/xxvd
	@chmod a+x $(TMPDIR)/$(ARCHIVE)/contrib/update-xxv
	@chmod a+x $(TMPDIR)/$(ARCHIVE)/contrib/at-vdradmin2xxv.pl
	@chmod a+x $(TMPDIR)/$(ARCHIVE)/locale/xgettext.pl
	@chmod a+x $(TMPDIR)/$(ARCHIVE)/etc/xxvd
	@chmod a+x $(TMPDIR)/$(ARCHIVE)/install.sh

dist: tmpfolder\
    updatesql\
    copyfiles\
    removefiles\
    updateversion\
    setpermission
	@chown root.root -R $(TMPDIR)/$(ARCHIVE)/*
	@tar czf $(PACKAGE).tgz --exclude=.svn -C $(TMPDIR) $(ARCHIVE)
	@-rm -rf $(TMPDIR)/$(ARCHIVE)
	@echo Distribution package created as $(PACKAGE).tgz

all: dist
