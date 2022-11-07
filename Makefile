CSR_CSV ?= csr.csv
CROSS_COMPILE ?= riscv64-unknown-elf-

all: output/boot.json

staging/csr.mk: $(CSR_CSV)
	mkdir -p staging
	scripts/csv2mk < $(CSR_CSV) > $@

include staging/csr.mk

staging/csr.dtsi: $(CSR_CSV)
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

BOOTARGS ?= $(CONSOLE_ARGS) $(ROOT_ARGS)

staging/linux-on-litex.dtb: linux-on-litex.dts staging/csr.dtsi $(wildcard dtsi/*.dtsi)
	mkdir -p staging
	gcc -E -x assembler-with-cpp -nostdinc -undef -D__DTS__ -DBOOTARGS="\"$(BOOTARGS)\"" -include staging/csr.dtsi - < linux-on-litex.dts | dtc -I dts -O dtb > $@

.PHONY: build-opensbi
opensbi/build/platform/generic/firmware/fw_payload.bin: staging/linux-on-litex.dtb
	$(MAKE) -C opensbi PLATFORM=generic CROSS_COMPILE="$(CROSS_COMPILE)" FW_FDT_PATH="$(PWD)"/staging/linux-on-litex.dtb FW_TEXT_START=$(MAIN_RAM_BASE)

opensbi/build/platform/generic/firmware/fw_payload.bin: build-opensbi

output/fw_payload.bin: opensbi/build/platform/generic/firmware/fw_payload.bin
	mkdir -p output
	cp $< $@

output/boot.json: boot.json.in output/fw_payload.bin
	mkdir -p output
	cp boot.json.in output/boot.json
	sed -i 's/@OPENSBI_ADDR@/$(MAIN_RAM_BASE)/g' output/boot.json

.PHONY: clean
clean:
	rm -rf opensbi/build
	rm -rf staging output
