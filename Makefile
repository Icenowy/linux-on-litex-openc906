CSR_CSV ?= csr.csv
CROSS_COMPILE ?= riscv64-unknown-elf-

all: output/boot.json

staging/csr.mk: $(CSR_CSV) scripts/csv2mk
	mkdir -p staging
	scripts/csv2mk < $(CSR_CSV) > $@

include staging/csr.mk

staging/csr.dtsi: $(CSR_CSV) scripts/csv2dtsi
	mkdir -p staging
	scripts/csv2dtsi < $(CSR_CSV) > $@

CONSOLE ?= liteuart
ROOT ?= /dev/mmcblk0p2

ifeq ($(CONSOLE),liteuart)
	CONSOLE_ARGS ?= console=liteuart earlycon=liteuart,$(UART_BASE)
endif
ifneq ($(ROOT),)
	ROOT_ARGS = root=$(ROOT)
endif

EXTRA_ARGS ?=

INITRD ?= $(wildcard initrd.img)

ifneq ($(INITRD),)
	INITRD_BASE = $(shell printf "0x%X" $$(($(MAIN_RAM_BASE) + 0x4000000)))
	INITRD_END = $(shell printf "0x%X" $$(($(INITRD_BASE) + $(shell wc -c $(INITRD) | awk '{print $$1}'))))
	INITRD_DEFINES = -DINITRD_BASE=$(INITRD_BASE) -DINITRD_END=$(INITRD_END)
endif

KERNEL_BASE = $(shell printf "0x%X" $$(($(MAIN_RAM_BASE) + 0x200000)))

BOOTARGS ?= $(CONSOLE_ARGS) $(ROOT_ARGS) $(EXTRA_ARGS)

staging/linux-on-litex.dtb: linux-on-litex.dts staging/csr.dtsi $(wildcard dtsi/*.dtsi)
	mkdir -p staging
	gcc -E -x assembler-with-cpp -nostdinc -undef -D__DTS__ -DBOOTARGS="\"$(BOOTARGS)\"" $(INITRD_DEFINES) -include staging/csr.dtsi - < linux-on-litex.dts > staging/linux-on-litex.dts
	dtc -I dts -O dtb < staging/linux-on-litex.dts > $@

opensbi/build/platform/generic/firmware/fw_jump.bin: staging/linux-on-litex.dtb
	rm -rf opensbi/build
	$(MAKE) -C opensbi PLATFORM=generic CROSS_COMPILE="$(CROSS_COMPILE)" FW_FDT_PATH="$(PWD)"/staging/linux-on-litex.dtb FW_TEXT_START=$(MAIN_RAM_BASE) FW_JUMP_ADDR=$(KERNEL_BASE)

linux/arch/riscv/boot/Image: linux-config
	cp linux-config linux/.config
	$(MAKE) -C linux ARCH=riscv CROSS_COMPILE="$(CROSS_COMPILE)"
	touch $@

output/Image: linux/arch/riscv/boot/Image
	mkdir -p output
	cp $< $@

output/fw_jump.bin: opensbi/build/platform/generic/firmware/fw_jump.bin
	mkdir -p output
	cp $< $@

output/boot.json output/initrd.img: boot.json.in output/fw_jump.bin output/Image $(INITRD)
	mkdir -p output
	cp boot.json.in output/boot.json
	sed -i 's/@OPENSBI_ADDR@/$(MAIN_RAM_BASE)/g' output/boot.json
	sed -i 's/@KERNEL_ADDR@/$(KERNEL_BASE)/g' output/boot.json
ifneq ($(INITRD),)
	cp $(INITRD) output/initrd.img
	sed -i 's/@INITRD_ADDR@/$(INITRD_BASE)/g' output/boot.json
else
	sed -i '/@INITRD_ADDR@/d' output/boot.json
endif

.PHONY: clean
clean:
	rm -rf opensbi/build
	rm -rf staging output
