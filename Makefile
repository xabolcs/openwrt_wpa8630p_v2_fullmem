# This Makefile downloads the OpenWrt ImageBuilder and patches
# the included tplink-safeloader to add more SupportList entries.
# Afterwards, the ImageBuilder can be used as normal.
#
# One advantage of this over from-source custom builds is that the 
# kernel is the same as the official builds, so all kmods from the 
# standard repos are installable.

ALL_CURL_OPTS := $(CURL_OPTS) -L --fail --create-dirs

VERSION := 21.02.7
BOARD := ramips
SUBTARGET := rt305x
SOC := rt5350
BUILDER := openwrt-imagebuilder-$(VERSION)-$(BOARD)-$(SUBTARGET).Linux-x86_64
PROFILES := hootoo_ht-tm01 hootoo_ht-tm02
PACKAGES := -wpad-mini -wpad-basic -wpad-basic-wolfssl wpad-mesh-wolfssl
PACKAGES += -ppp -ppp-mod-pppoe
PACKAGES += uboot-envtools
EXTRA_IMAGE_NAME := stocklayout+mesh+noppp
BASE_FILES := $(subst $(CURDIR)/,,$(wildcard $(CURDIR)/files/*))

TOPDIR := $(CURDIR)/$(BUILDER)
KDIR := $(TOPDIR)/build_dir/target-mipsel_24kc_musl/linux-$(BOARD)_$(SUBTARGET)
PATH := $(TOPDIR)/staging_dir/host/bin:$(PATH)
LINUX_VERSION = $(shell sed -n -e '/Linux-Version: / {s/Linux-Version: //p;q}' $(BUILDER)/.targetinfo)


all: images


$(BUILDER).tar.xz:
	curl $(ALL_CURL_OPTS) -O https://downloads.openwrt.org/releases/$(VERSION)/targets/$(BOARD)/$(SUBTARGET)/$(BUILDER).tar.xz


$(BUILDER): $(BUILDER).tar.xz
	tar -xf $(BUILDER).tar.xz

	# Fetch OpenWrt sources to apply patches
	curl $(ALL_CURL_OPTS) "https://git.openwrt.org/?p=openwrt/openwrt.git;hb=refs/tags/v$(VERSION);a=blob_plain;f=package/boot/uboot-envtools/files/ramips" -o $(BUILDER)/package/boot/uboot-envtools/files/ramips
	mkdir $(BUILDER)/target/linux/ramips/rt305x/base-files/etc/uci-defaults
	touch $(BUILDER)/target/linux/ramips/rt305x/base-files/etc/uci-defaults/05_fix-compat-version
	touch $(BUILDER)/target/linux/ramips/dts/rt5350_hootoo_ht-tm01.dts
	touch $(BUILDER)/target/linux/ramips/dts/rt5350_sunvalley_tripmate.dtsi

	# Apply all patches
	$(foreach file, $(sort $(wildcard patches/*.patch)), patch -d $(BUILDER) --posix -p1 < $(file);)
	
	# Regenerate .targetinfo
	cd $(BUILDER) && make -f include/toplevel.mk TOPDIR="$(TOPDIR)" prepare-tmpinfo || true
	cp -f $(BUILDER)/tmp/.targetinfo $(BUILDER)/.targetinfo

ifneq "$(strip $(BASE_FILES))" ""
base-files: $(BASE_FILES)
	$(info base-files are "$(BASE_FILES)")
	cp -pvur $(BASE_FILES) $(TOPDIR)/target/linux/$(BOARD)/$(SUBTARGET)/base-files
else
base-files:
endif

linux-sources: $(BUILDER)
	# Fetch DTS includes and other kernel source files
	curl $(ALL_CURL_OPTS) "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/include/dt-bindings/gpio/gpio.h?h=v$(LINUX_VERSION)" -o linux-sources.tmp/include/dt-bindings/gpio/gpio.h
	curl $(ALL_CURL_OPTS) "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/include/dt-bindings/input/input.h?h=v$(LINUX_VERSION)" -o linux-sources.tmp/include/dt-bindings/input/input.h
	curl $(ALL_CURL_OPTS) "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/include/uapi/linux/input-event-codes.h?h=v$(LINUX_VERSION)" -o linux-sources.tmp/include/dt-bindings/input/linux-event-codes.h
	rm -rf linux-sources
	mv -T linux-sources.tmp linux-sources


images: $(BUILDER) linux-sources base-files
	# Build this device's DTB and firmware kernel image. Uses the official kernel build as a base.
	ln -sf /usr/bin/cpp $(BUILDER)/staging_dir/host/bin/mipsel-openwrt-linux-musl-cpp
	ln -sf ../../../../../linux-sources/include $(KDIR)/linux-$(LINUX_VERSION)/include
	cd $(BUILDER) && $(foreach PROFILE,$(PROFILES),\
	    env PATH=$(PATH) make --trace -C target/linux/$(BOARD)/image $(KDIR)/$(PROFILE)-kernel.bin TOPDIR="$(TOPDIR)" INCLUDE_DIR="$(TOPDIR)/include" TARGET_BUILD=1 BOARD="$(BOARD)" SUBTARGET="$(SUBTARGET)" PROFILE="$(PROFILE)" DEVICE_DTS="$(SOC)_$(PROFILE)"\
	;)
	
	# Use ImageBuilder as normal
	cd $(BUILDER) && $(foreach PROFILE,$(PROFILES),\
	    make image PROFILE="$(PROFILE)" EXTRA_IMAGE_NAME="$(EXTRA_IMAGE_NAME)" PACKAGES="$(PACKAGES)" FILES="$(TOPDIR)/target/linux/$(BOARD)/$(SUBTARGET)/base-files/"\
	;)
	sleep 5
	cat $(BUILDER)/bin/targets/$(BOARD)/$(SUBTARGET)/sha256sums
	ls -hs --block-size=K $(BUILDER)/bin/targets/$(BOARD)/$(SUBTARGET)/openwrt-*.bin


clean:
	rm -rf openwrt-imagebuilder-* linux-sources linux-sources.tmp
