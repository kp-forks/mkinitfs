VERSION		:= 3.12.0

sbindir		?= /sbin
sysconfdir	?= /etc/mkinitfs
datarootdir	?= /usr/share
datadir		?= $(datarootdir)/mkinitfs
mandir		?= $(datarootdir)/man

SBIN_FILES	:= mkinitfs bootchartd nlplug-findfs/nlplug-findfs
SHARE_FILES	:= initramfs-init fstab passwd group
CONF_FILES	:= mkinitfs.conf \
		features.d/9p.modules \
		features.d/ata.modules \
		features.d/aoe.modules \
		features.d/base.files \
		features.d/base.modules \
		features.d/bootchart.files \
		features.d/btrfs.files \
		features.d/btrfs.modules \
		features.d/cdrom.modules \
		features.d/cramfs.modules \
		features.d/cryptkey.files \
		features.d/cryptsetup.files \
		features.d/cryptsetup.modules \
		features.d/ena.modules \
		features.d/ext2.modules \
		features.d/ext3.modules \
		features.d/ext4.modules \
		features.d/f2fs.modules \
		features.d/floppy.modules \
		features.d/gfs2.modules \
		features.d/jfs.modules \
		features.d/keymap.files \
		features.d/kms.modules \
		features.d/lvm-thin.files \
		features.d/lvm.files \
		features.d/lvm.modules \
		features.d/mmc.modules \
		features.d/nbd.files \
		features.d/nbd.modules \
		features.d/nfit.modules \
		features.d/network.files \
		features.d/network.modules \
		features.d/nvme.modules \
		features.d/ocfs2.modules \
		features.d/raid.files \
		features.d/raid.modules \
		features.d/reiserfs.modules \
		features.d/scsi.modules \
		features.d/squashfs.modules \
		features.d/ubifs.modules \
		features.d/usb.modules \
		features.d/virtio.modules \
		features.d/xenpci.modules \
		features.d/xfs.files \
		features.d/xfs.modules \
		features.d/zfs.files \
		features.d/zfs.modules \
		features.d/qeth.modules \
		features.d/dasd_mod.modules \
		features.d/zfcp.modules \
		features.d/dhcp.files \
		features.d/dhcp.modules \
		features.d/https.files \
		features.d/wireguard.files \
		features.d/wireguard.modules \
		features.d/phy.modules
MAN_FILES       := mkinitfs.1 mkinitfs-bootparam.7 nlplug-findfs.1

SCRIPTS		:= mkinitfs bootchartd initramfs-init
IN_FILES	:= $(addsuffix .in,$(SCRIPTS) $(MAN_FILES))

GIT_REV := $(shell test -d .git && git describe || echo exported)
ifneq ($(GIT_REV), exported)
FULL_VERSION    := $(patsubst $(PACKAGE)-%,%,$(GIT_REV))
FULL_VERSION    := $(patsubst v%,%,$(FULL_VERSION))
else
FULL_VERSION    := $(VERSION)
endif


DISTFILES	:= $(IN_FILES) $(CONF_FILES) Makefile

INSTALL		:= install
SED		:= sed
SED_REPLACE	:= -e 's:@VERSION@:$(FULL_VERSION):g' \
		-e 's:@sysconfdir@:$(sysconfdir):g' \
		-e 's:@datadir@:$(datadir):g'

DEFAULT_FEATURES ?= ata base cdrom ext4 keymap kms mmc nvme raid scsi usb virtio
ifeq ($(shell uname -m), s390x)
DEFAULT_FEATURES += qeth dasd_mod zfcp
endif
ifeq ($(shell uname -m), aarch64)
DEFAULT_FEATURES += phy
endif


all:	$(SBIN_FILES) $(SCRIPTS) $(CONF_FILES) $(MAN_FILES)

clean:
	rm -fr $(SBIN_FILES) $(SCRIPTS) $(MAN_FILES) mkinitfs.conf \
		nlplug-findfs/actual nlplug-findfs/build

help:
	@echo mkinitfs $(VERSION)
	@echo "usage: make install [DESTDIR=]"

CFLAGS ?= -Wall -Werror -g
CFLAGS += -D_GNU_SOURCE -DDEBUG

PKGCONF		?= pkg-config
BLKID_CFLAGS	:= $(shell $(PKGCONF) --cflags blkid)
BLKID_LIBS	:= $(shell $(PKGCONF) --libs blkid)
LIBKMOD_CFLAGS	:= $(shell $(PKGCONF) --cflags libkmod)
LIBKMOD_LIBS	:= $(shell $(PKGCONF) --libs libkmod)
CRYPTSETUP_CFLAGS := $(shell $(PKGCONF) --cflags libcryptsetup)
CRYPTSETUP_LIBS	:= $(shell $(PKGCONF) --libs libcryptsetup)

CFLAGS		+= $(BLKID_CFLAGS) $(LIBKMOD_CFLAGS) $(CRYPTSETUP_CFLAGS)
LIBS		= $(BLKID_LIBS) $(LIBKMOD_LIBS) $(CRYPTSETUP_LIBS)

%.o: %.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ -c $<

nlplug-findfs/nlplug-findfs: nlplug-findfs/nlplug-findfs.o
	$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)

check-nlplug-findfs: nlplug-findfs/build
	nlplug-findfs/test.sh run

nlplug-findfs/build: nlplug-findfs/init.sh nlplug-findfs/nlplug-findfs nlplug-findfs/test.sh
	nlplug-findfs/test.sh build

tests/Kyuafile: $(wildcard tests/*.test)
	echo "syntax(2)" > $@.tmp
	echo "test_suite('mkinitfs')" >> $@.tmp
	for i in $(notdir $(wildcard tests/*.test)); do \
		echo "atf_test_program{name='$$i',timeout=5}" >> $@.tmp ; \
	done
	mv $@.tmp $@

Kyuafile:
	echo "syntax(2)" > $@.tmp
	echo "test_suite('mkinitfs')" >> $@.tmp
	echo "include('tests/Kyuafile')" >> $@.tmp
	mv $@.tmp $@

check: tests/Kyuafile Kyuafile mkinitfs initramfs-init
	kyua --variable parallelism=$(shell nproc) test \
		|| { kyua report --verbose && exit 1; }

.SUFFIXES:	.in
.in:
	${SED} ${SED_REPLACE} ${SED_EXTRA} $< > $@.tmp
	chmod +x $@.tmp
	mv $@.tmp $@

install: $(SBIN_FILES) $(SHARE_FILES) $(CONF_FILES)
	install -d -m755 $(DESTDIR)/$(sbindir)
	for i in $(SBIN_FILES); do \
		$(INSTALL) -Dm755 $$i $(DESTDIR)/$(sbindir)/;\
	done
	for i in $(CONF_FILES); do \
		$(INSTALL) -Dm644 $$i $(DESTDIR)/$(sysconfdir)/$$i;\
	done
	for i in $(SHARE_FILES); do \
		$(INSTALL) -Dm644 $$i $(DESTDIR)/$(datadir)/$$i;\
	done
	for i in $(MAN_FILES); do \
		$(INSTALL) -Dm644 $$i $(DESTDIR)$(mandir)/man$${i##*.}/$$i;\
	done

mkinitfs.conf:
	echo 'features="$(DEFAULT_FEATURES)"' > $@

.PHONY: all check clean help install
