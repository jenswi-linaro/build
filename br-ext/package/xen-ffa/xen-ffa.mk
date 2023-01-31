################################################################################
#
# Xen-ffa
#
################################################################################

XEN_FFA_VERSION = xen_ffa-v6
XEN_FFA_SITE = https://github.com/jenswi-linaro/xen.git
XEN_FFA_SITE_METHOD = git
XEN_FFA_LICENSE = GPL-2.0
XEN_FFA_LICENSE_FILES = COPYING
XEN_FFA_CPE_ID_VENDOR = xen
XEN_FFA_CPE_ID_PREFIX = cpe:2.3:o
XEN_FFA_DEPENDENCIES = host-acpica host-python3 host-meson host-pkgconf libglib2 zlib pixman

#Disable hash check
BR_NO_CHECK_HASH_FOR += $(XEN_FFA_SOURCE)

# Calculate XEN_FFA_ARCH
ifeq ($(ARCH),aarch64)
XEN_FFA_ARCH = arm64
else ifeq ($(ARCH),arm)
XEN_FFA_ARCH = arm32
endif

XEN_FFA_CONF_OPTS = \
	--disable-golang \
	--disable-ocamltools \
	--with-initddir=/etc/init.d

XEN_FFA_CONF_ENV = PYTHON=$(HOST_DIR)/bin/python3
XEN_FFA_MAKE_ENV = \
	XEN_TARGET_ARCH=$(XEN_FFA_ARCH) \
	CROSS_COMPILE=$(TARGET_CROSS) \
	HOST_EXTRACFLAGS="-Wno-error" \
	XEN_HAS_CHECKPOLICY=n \
	$(TARGET_CONFIGURE_OPTS)

ifeq ($(BR2_PACKAGE_XEN_FFA_HYPERVISOR),y)
XEN_FFA_MAKE_OPTS += dist-xen
XEN_FFA_INSTALL_IMAGES = YES
define XEN_FFA_INSTALL_IMAGES_CMDS
	cp $(@D)/xen/xen $(BINARIES_DIR)
endef
else
XEN_FFA_CONF_OPTS += --disable-xen
endif

ifeq ($(BR2_PACKAGE_XEN_FFA_TOOLS),y)
XEN_FFA_DEPENDENCIES += \
	dtc libaio libglib2 ncurses openssl pixman slirp util-linux yajl
ifeq ($(BR2_PACKAGE_ARGP_STANDALONE),y)
XEN_FFA_DEPENDENCIES += argp-standalone
endif
XEN_FFA_INSTALL_TARGET_OPTS += DESTDIR=$(TARGET_DIR) install-tools
XEN_FFA_MAKE_OPTS += dist-tools

define XEN_FFA_INSTALL_INIT_SYSV
	mv $(TARGET_DIR)/etc/init.d/xencommons $(TARGET_DIR)/etc/init.d/S50xencommons
	mv $(TARGET_DIR)/etc/init.d/xen-watchdog $(TARGET_DIR)/etc/init.d/S50xen-watchdog
	mv $(TARGET_DIR)/etc/init.d/xendomains $(TARGET_DIR)/etc/init.d/S60xendomains
endef

XEN_FFA_CONF_OPTS += --with-system-qemu
XEN_FFA_INSTALL_STAGING = YES
else
XEN_FFA_INSTALL_TARGET = NO
XEN_FFA_CONF_OPTS += --disable-tools
endif

$(eval $(autotools-package))
