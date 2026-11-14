BR2_EXTERNAL_DIR := $(CURDIR)/external
BUILDROOT_DIR    := $(CURDIR)/buildroot
OUTPUT_DIR       := $(CURDIR)/output
BUILDROOT_REPO   ?= https://github.com/buildroot/buildroot.git
BUILDROOT_BRANCH ?= 2024.02.x
DEFCONFIG        ?= gsat_headless_arm1176_defconfig

BR2_EXTERNAL := $(BR2_EXTERNAL_DIR)

.PHONY: all buildroot defconfig build run verify ssh clean distclean help

all: build

help:
	@echo "make buildroot   clone Buildroot $(BUILDROOT_BRANCH) into ./buildroot"
	@echo "make defconfig   apply $(DEFCONFIG)"
	@echo "make build       build everything (implies defconfig)"
	@echo "make verify      check account/console/ssh in the built image"
	@echo "make run         boot output/images/* under QEMU"
	@echo "make ssh         ssh into the running QEMU guest on :2222"
	@echo "make menuconfig  interactive configuration"
	@echo "make distclean   delete output/ (keeps buildroot/ and sources)"

buildroot: $(BUILDROOT_DIR)/Makefile

$(BUILDROOT_DIR)/Makefile:
	git clone --depth 1 -b $(BUILDROOT_BRANCH) $(BUILDROOT_REPO) $(BUILDROOT_DIR)

defconfig: buildroot
	$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) $(DEFCONFIG)

build: defconfig
	$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL)

menuconfig: defconfig
	$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) menuconfig

verify:
	./scripts/verify-image.sh $(OUTPUT_DIR)/images/rootfs.ext2

run:
	./scripts/qemu-run.sh

ssh:
	ssh -p 2222 -o StrictHostKeyChecking=no gsat-mb86h615@127.0.0.1

clean:
	-$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) clean

distclean:
	rm -rf $(OUTPUT_DIR)
