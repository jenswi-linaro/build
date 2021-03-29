################################################################################
# Following variables defines how the NS_USER (Non Secure User - Client
# Application), NS_KERNEL (Non Secure Kernel), S_KERNEL (Secure Kernel) and
# S_USER (Secure User - TA) are compiled
################################################################################
COMPILE_NS_USER   ?= 64
override COMPILE_NS_KERNEL := 64
COMPILE_S_USER    ?= 64
COMPILE_S_KERNEL  ?= 64

OPTEE_OS_PLATFORM = vexpress-fvp

include common.mk

DEBUG=1

################################################################################
# Paths to git projects and various binaries
################################################################################
TF_A_PATH		?= $(ROOT)/trusted-firmware-a
ifeq ($(DEBUG),1)
TF_A_BUILD		?= debug
else
TF_A_BUILD		?= release
endif
HAFNIUM_PATH		?= $(ROOT)/hafnium
EDK2_PATH		?= $(ROOT)/edk2
EDK2_PLATFORMS_PATH	?= $(ROOT)/edk2-platforms
EDK2_TOOLCHAIN		?= GCC49
EDK2_ARCH		?= AARCH64
ifeq ($(DEBUG),1)
EDK2_BUILD		?= DEBUG
else
EDK2_BUILD		?= RELEASE
endif
EDK2_BIN		?= $(EDK2_PLATFORMS_PATH)/Build/ArmVExpress-FVP-AArch64/$(EDK2_BUILD)_$(EDK2_TOOLCHAIN)/FV/FVP_$(EDK2_ARCH)_EFI.fd
GRUB_PATH		?= $(ROOT)/grub
GRUB_CONFIG_PATH	?= $(BUILD_PATH)/fvp/grub
OUT_PATH		?= $(ROOT)/out
GRUB_BIN		?= $(OUT_PATH)/bootaa64.efi
BOOT_IMG		?= $(OUT_PATH)/boot-fat.uefi.img
SPMC_MANIFEST_FILE	?= $(TF_A_PATH)/plat/arm/board/fvp/fdts/fvp_spmc_optee_sp_manifest.dts

################################################################################
# Targets
################################################################################
all: edk2 arm-tf boot-img grub linux optee-os hafnium
clean: arm-tf-clean boot-img-clean buildroot-clean edk2-clean grub-clean \
	optee-os-clean


include toolchain.mk

################################################################################
# Folders
################################################################################
$(OUT_PATH):
	mkdir -p $@

################################################################################
# ARM Trusted Firmware
################################################################################
TF_A_EXPORTS ?= \
	CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)"

TF_A_FLAGS ?= \
	SPD=spmd \
	CTX_INCLUDE_EL2_REGS=1 \
	SPMD_SPM_AT_SEL2=1 \
	PLAT=fvp \
	BL33=$(EDK2_BIN) \
	DEBUG=$(DEBUG) \
	BL32=$(HAFNIUM_PATH)/out/reference/secure_aem_v8a_fvp_clang/hafnium.bin \
	ARM_ARCH_MINOR=4 \
	SP_LAYOUT_FILE=$(TF_A_PATH)/sp_layout.json \
	ARM_SPMC_MANIFEST_DTS=$(SPMC_MANIFEST_FILE)

arm-tf: edk2 optee-os hafnium
	$(TF_A_EXPORTS) $(MAKE) -C $(TF_A_PATH) $(TF_A_FLAGS) all fip

arm-tf-clean:
	$(TF_A_EXPORTS) $(MAKE) -C $(TF_A_PATH) $(TF_A_FLAGS) clean

################################################################################
# Hafnium
################################################################################

HAFNIUM_EXPORTS ?= \
	CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)"

HAFNIUM_FLAGS ?=

HAFNIUM_PROJECT_REFERENCE ?= \
	https://git.trustedfirmware.org/hafnium/project/reference.git

$(HAFNIUM_PATH)/.init_stuff:
	(cd $(HAFNIUM_PATH) && git submodule update --init --recursive)
	touch $(HAFNIUM_PATH)/.init_stuff

hafnium_base: $(HAFNIUM_PATH)/.init_stuff | $(OUT_PATH)
	$(HAFNIUM_EXPORTS) $(MAKE) -C $(HAFNIUM_PATH) $(HAFNIUM_FLAGS) all
	cp $(HAFNIUM_PATH)/out/reference/aem_v8a_fvp_clang/hafnium.bin \
		$(OUT_PATH)/hafnium.bin
	cp $(HAFNIUM_PATH)/out/reference/secure_aem_v8a_fvp_clang/hafnium.bin \
		$(OUT_PATH)/secure_hafnium.bin

hafnium: hafnium_base #hafnium_ramdisk

# Not currently using Hafnium in normal world.
hafnium_ramdisk $(OUT_PATH)/normal_world.dtb $(OUT_PATH)/initrd.img: buildroot linux | $(OUT_PATH)
	mkdir -p $(OUT_PATH)/initrd
	dtc -O dtb -o $(OUT_PATH)/initrd/manifest.dtb \
		$(TF_A_PATH)/fdts/inner_initrd.dts
	# TODO Link and --dereference
	cp ${ROOT}/out-br/images/rootfs.cpio.gz $(OUT_PATH)/initrd/initrd.img
	cp $(LINUX_PATH)/arch/arm64/boot/Image $(OUT_PATH)/initrd/vmlinuz
	(cd $(OUT_PATH)/initrd && \
	 printf "manifest.dtb\ninitrd.img\nvmlinuz" | cpio -o > ../initrd.img)
	cp $(TF_A_PATH)/fdts/normal_world_single.dts \
		$(OUT_PATH)/normal_world.dts
	sh $(ROOT)/build/fvp/print_dts_epilogue.sh 0x84000000 \
		`stat -c%s "$(OUT_PATH)/initrd.img"` >> \
		$(OUT_PATH)/normal_world.dts
	dtc -O dtb -o $(OUT_PATH)/normal_world.dtb $(OUT_PATH)/normal_world.dts

################################################################################
# EDK2 / Tianocore
################################################################################
define edk2-env
	export WORKSPACE=$(EDK2_PLATFORMS_PATH)
endef

define edk2-call
	$(EDK2_TOOLCHAIN)_$(EDK2_ARCH)_PREFIX=$(AARCH64_CROSS_COMPILE) \
	build -n `getconf _NPROCESSORS_ONLN` -a $(EDK2_ARCH) \
		-t $(EDK2_TOOLCHAIN) -p Platform/ARM/VExpressPkg/ArmVExpress-FVP-AArch64.dsc -b $(EDK2_BUILD)
endef

edk2: edk2-common

edk2-clean: edk2-clean-common

################################################################################
# Linux kernel
################################################################################
LINUX_DEFCONFIG_COMMON_ARCH := arm64
LINUX_DEFCONFIG_COMMON_FILES := \
		$(LINUX_PATH)/arch/arm64/configs/defconfig \
		$(CURDIR)/kconfigs/fvp.conf

linux-defconfig: $(LINUX_PATH)/.config

LINUX_COMMON_FLAGS += ARCH=arm64

linux: linux-common

linux-defconfig-clean: linux-defconfig-clean-common

LINUX_CLEAN_COMMON_FLAGS += ARCH=arm64

linux-clean: linux-clean-common

LINUX_CLEANER_COMMON_FLAGS += ARCH=arm64

linux-cleaner: linux-cleaner-common

################################################################################
# OP-TEE
################################################################################
OPTEE_OS_COMMON_FLAGS += CFG_ARM_GICV3=y
OPTEE_OS_COMMON_FLAGS += CFG_TEE_CORE_LOG_LEVEL=3 DEBUG=1 CFG_TEE_BENCHMARK=n
OPTEE_OS_COMMON_FLAGS += CFG_CORE_BGET_BESTFIT=y
OPTEE_OS_COMMON_FLAGS += CFG_CORE_SEL2_SPMC=y
#OPTEE_OS_COMMON_FLAGS += CFG_CORE_SEL1_SPMC=y
optee-os: optee-os-common

optee-os-clean: optee-os-clean-common

################################################################################
# grub
################################################################################
grub-flags := CC="$(CCACHE)gcc" \
	TARGET_CC="$(AARCH64_CROSS_COMPILE)gcc" \
	TARGET_OBJCOPY="$(AARCH64_CROSS_COMPILE)objcopy" \
	TARGET_NM="$(AARCH64_CROSS_COMPILE)nm" \
	TARGET_RANLIB="$(AARCH64_CROSS_COMPILE)ranlib" \
	TARGET_STRIP="$(AARCH64_CROSS_COMPILE)strip" \
	--disable-werror

GRUB_MODULES += boot chain configfile echo efinet eval ext2 fat font gettext \
		gfxterm gzio help linux loadenv lsefi normal part_gpt \
		part_msdos read regexp search search_fs_file search_fs_uuid \
		search_label terminal terminfo test tftp time

$(GRUB_PATH)/configure: $(GRUB_PATH)/configure.ac
	cd $(GRUB_PATH) && ./autogen.sh

$(GRUB_PATH)/Makefile: $(GRUB_PATH)/configure
	cd $(GRUB_PATH) && ./configure --target=aarch64 --enable-boot-time $(grub-flags)

.PHONY: grub
grub: $(GRUB_PATH)/Makefile | $(OUT_PATH)
	$(MAKE) -C $(GRUB_PATH) && \
	cd $(GRUB_PATH) && ./grub-mkimage \
		--output=$(GRUB_BIN) \
		--config=$(GRUB_CONFIG_PATH)/grub.cfg \
		--format=arm64-efi \
		--directory=grub-core \
		--prefix=/boot/grub \
		$(GRUB_MODULES)

.PHONY: grub-clean
grub-clean:
	@if [ -e $(GRUB_PATH)/Makefile ]; then $(MAKE) -C $(GRUB_PATH) clean; fi
	@rm -f $(GRUB_BIN)
	@rm -f $(GRUB_PATH)/configure


################################################################################
# Boot Image
################################################################################
.PHONY: boot-img
boot-img: linux grub buildroot arm-tf
	rm -f $(BOOT_IMG)
	mformat -i $(BOOT_IMG) -n 64 -h 255 -T 131072 -v "BOOT IMG" -C ::
	mcopy -i $(BOOT_IMG) $(LINUX_PATH)/arch/arm64/boot/Image ::
	mcopy -i $(BOOT_IMG) $(TF_A_PATH)/build/fvp/$(TF_A_BUILD)/fdts/fvp-base-gicv3-psci.dtb ::
	mmd -i $(BOOT_IMG) ::/EFI
	mmd -i $(BOOT_IMG) ::/EFI/BOOT
	mcopy -i $(BOOT_IMG) $(ROOT)/out-br/images/rootfs.cpio.gz ::/initrd.img
	mcopy -i $(BOOT_IMG) $(GRUB_BIN) ::/EFI/BOOT/bootaa64.efi
	mcopy -i $(BOOT_IMG) $(GRUB_CONFIG_PATH)/grub.cfg ::/EFI/BOOT/grub.cfg

.PHONY: boot-img-clean
boot-img-clean:
	rm -f $(BOOT_IMG)

################################################################################
# Run targets
################################################################################
# This target enforces updating root fs etc
run: all
	$(MAKE) run-only

run-only:
	$(ROOT)/model/Base_RevC_AEMv8A_pkg/models/Linux64_GCC-6.4//FVP_Base_RevC-2xAEMv8A \
	-C pctl.startup=0.0.0.0 \
	-C bp.secure_memory=0 \
	-C cluster0.NUM_CORES=4 \
	-C cluster1.NUM_CORES=4 \
	-C cache_state_modelled=0 \
	-C bp.pl011_uart0.untimed_fifos=1 \
	-C bp.pl011_uart0.unbuffered_output=1 \
	-C bp.pl011_uart1.untimed_fifos=1 \
	-C bp.pl011_uart1.unbuffered_output=1 \
	-C bp.pl011_uart0.out_file=$(OUT_PATH)/uart0.log \
	-C bp.pl011_uart1.out_file=$(OUT_PATH)/uart1.log \
	-C bp.terminal_0.start_telnet=1 \
	-C bp.terminal_1.start_telnet=1 \
	-C bp.vis.disable_visualisation=0 \
	-C bp.secureflashloader.fname=$(TF_A_PATH)/build/fvp/$(TF_A_BUILD)/bl1.bin \
	-C bp.flashloader0.fname=$(TF_A_PATH)/build/fvp/$(TF_A_BUILD)/fip.bin \
	-C bp.ve_sysregs.mmbSiteDefault=0 \
	-C bp.ve_sysregs.exit_on_shutdown=1 \
	-C cluster0.has_arm_v8-4=1 \
	-C cluster1.has_arm_v8-4=1 \
	-C bp.virtioblockdevice.image_path=$(BOOT_IMG)
