################################################################################
#
# Makefile -- for building vdr2jpeg
#
# Copyright (c) 2005-2015 Andreas Brachold
#
# This code is distributed under the terms and conditions of the
# GNU GENERAL PUBLIC LICENSE. See the file COPYING for details.
#


# You can change the compile options here 
# or add options at own file Make.config

# Place where ffmpeg was installed
FFMPEG_BIN ?= ffmpeg

# Build with debugging symbol and lots of dumped messages
#DEBUG = 1

# Build full static paket, 
#STATIC = 1

# Place where vdr2jpeg should installed
INSTALLBINDIR ?= /usr/local/bin

# Place where should package created, need some space.
TMPDIR = /tmp

################################################################################
#
# there none user configurable options below this point
#
################################################################################
ifdef DESTDIR
INSTALLDIR = $(DESTDIR)/$(INSTALLBINDIR)
else
INSTALLDIR = $(INSTALLBINDIR)
endif
################################################################################
# Compiler/linker settings
CXX      ?= g++
STRIP    ?= strip

# Allow user defined options to overwrite defaults:
-include Make.config

# General settings:

ifdef DEBUG
	CXXFLAGS ?= -O0
	CXXFLAGS += -g -ggdb
	LDFLAGS += -g -ggdb
	DEFINES += -DDEBUG
else
	CXXFLAGS ?= -O2
endif
CXXFLAGS += -fPIC -Wall -Woverloaded-virtual

ifdef STATIC
    CXXFLAGS += -static
endif

################################################################################
# Target configuration

PRGNAME = vdr2jpeg
VERSION = $(shell grep 'static const char \*VERSION *=' vdr2jpeg.cpp | awk '{ print $$6 }' | sed -e 's/[";]//g')
ARCHIVE = $(PRGNAME)-$(VERSION)
DEFINES += -DFFMPEG_BIN=\"$(FFMPEG_BIN)\" -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_GNU_SOURCE -D__STDC_CONSTANT_MACROS
FILES = README LIESMICH HISTORY COPYING Makefile \
	vdr2jpeg.cpp \
	gop.cpp gop.h \
	mpegdec.cpp mpegdec.h \
	ffm.cpp ffm.h \
	tools.cpp tools.h
OBJS = vdr2jpeg.o tools.o gop.o mpegdec.o ffm.o

################################################################################
# Implicit rules:

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $(DEFINES) $(INCLUDES) $<


################################################################################
# Main targets :

all:    vdr2jpeg
.PHONY: all

vdr2jpeg: $(OBJS)
	$(CXX) $(CXXFLAGS) $(OBJS) $(LIBS) -o vdr2jpeg
ifndef DEBUG
	$(STRIP) $@	
endif

install: all
	install -d $(INSTALLDIR)
	install -m 755 -o root -g root -s vdr2jpeg $(INSTALLDIR)

uninstall:
	rm -f $(INSTALLDIR)/vdr2jpeg

clean:
	@-rm -f vdr2jpeg a.out *.o *.tgz core* *~

distclean:  clean
	@-rm -f *.jpg *.mpv

dist:	distclean
	@-rm -rf $(TMPDIR)/$(ARCHIVE)
	@mkdir -p $(TMPDIR)/$(ARCHIVE)
	@cp -a $(FILES) $(TMPDIR)/$(ARCHIVE)
	@find $(TMPDIR)/$(ARCHIVE) -type d -exec chmod 755 {} \;
	@find $(TMPDIR)/$(ARCHIVE) -type f -exec chmod 644 {} \;
	@chown root.root -R $(TMPDIR)/$(ARCHIVE)/*
	@tar czfh $(ARCHIVE).tgz -C $(TMPDIR) $(ARCHIVE) 
	@-rm -rf $(TMPDIR)/$(ARCHIVE)
	@echo Distribution package created as $(ARCHIVE).tgz
