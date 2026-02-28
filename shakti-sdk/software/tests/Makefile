SHELL := /bin/bash # Use bash syntax

export XLEN
export MABI
export MARCH
export FLAGS
export DC
export filepath

# appln and target board
PROGRAM ?=all
TARGET ?=artix7_100t
DEBUG ?=
XLEN ?=32
filepath ?=
D ?=
openocd ?= $(shell which openocd)

GENLIB:=$(shell pwd)/

all: check library do run_gdb finish
	@echo "All done"

check:
ifeq ($(DEBUG),DEBUG)
	@$(eval D = -g)
endif

ifeq ($(TARGET),artix7_35t)
	@$(eval XLEN = 32)
	@$(eval WIDTH = 4)
	@$(eval FLAGS=-Wall -Wextra -Wshadow -Wpointer-arith -Wbad-function-cast -Wcast-align -Wsign-compare -Waggregate-return -Wstrict-prototypes -Wmissing-prototypes -Wmissing-declarations -Wunused  -D ARTIX7_35T)
	@$(eval MARCH=rv32imac)
	@$(eval MABI=ilp32)
	@$(eval INTERFACE=$(bspboard)/ftdi)
	@$(eval DC =$(FLAGS) $(D) )
else
ifeq ($(TARGET),artix7_100t)
	@$(eval XLEN = 64)
	@$(eval WIDTH = 8)
	@$(eval FLAGS= -D ARTIX7_100T)
	@$(eval MARCH=rv64imac)
	@$(eval MABI=lp64)
	@$(eval INTERFACE=$(bspboard)/ftdi)
	@$(eval DC =$(FLAGS) $(D))
endif
endif

library:
	@if [ -z "$(CLEAR)" ]; then make compile build; fi

compile:
	@mkdir -p ./gen_lib
	@riscv$(XLEN)-unknown-elf-gcc -march=$(MARCH) -mabi=$(MABI) $(DC) -mcmodel=medany -static -std=gnu99 -fno-builtin-printf -I$(bspinc) -c $(bsplib)/util.c -o ./gen_lib/util.o -lm -lgcc
	@riscv$(XLEN)-unknown-elf-gcc -march=$(MARCH) -mabi=$(MABI) $(DC) -mcmodel=medany -static -std=gnu99 -fno-builtin-printf -I$(bspinc) -c $(bspcore)/traps.c -o ./gen_lib/traps.o -lm -lgcc
	@riscv$(XLEN)-unknown-elf-gcc -march=$(MARCH) -mabi=$(MABI) $(DC) -mcmodel=medany -static -std=gnu99 -fno-builtin-printf -I$(bspinc) -c $(bspdri)/qspi/qspi_micron.c -o ./gen_lib/qspi_micron.o -lm -lgcc
	@riscv$(XLEN)-unknown-elf-gcc -march=$(MARCH) -mabi=$(MABI) $(DC) -mcmodel=medany -static -std=gnu99 -fno-builtin-printf -I$(bspinc) -I$(bspboard) -c $(bspdri)/pwm/pwm_driver.c -o ./gen_lib/pwm_driver.o -lm -lgcc
	@riscv$(XLEN)-unknown-elf-gcc -march=$(MARCH) -mabi=$(MABI) $(DC) -mcmodel=medany -static -std=gnu99 -fno-builtin-printf -I$(bspinc) -I$(bspboard) -c $(bspdri)/xadc/xadc_driver.c -o ./gen_lib/xadc_driver.o -lm -lgcc
	@riscv$(XLEN)-unknown-elf-gcc -march=$(MARCH) -mabi=$(MABI) $(DC) -mcmodel=medany -static -std=gnu99 -fno-builtin-printf -I$(bspinc) -I$(bspboard) -c $(bspdri)/uart/uart.c -o ./gen_lib/uart.o -lm -lgcc
	@riscv$(XLEN)-unknown-elf-gcc -march=$(MARCH) -mabi=$(MABI) $(DC) -mcmodel=medany -static -std=gnu99 -fno-builtin-printf -I$(bspinc) -I$(bspboard) -c $(bspdri)/i2c/i2c_driver.c -o ./gen_lib/i2c_driver.o -lm -lgcc
	@riscv$(XLEN)-unknown-elf-gcc -march=$(MARCH) -mabi=$(MABI) $(DC) -mcmodel=medany -static -std=gnu99 -fno-common -fno-builtin-printf -D__ASSEMBLY__=1 -I$(bspinc) -c $(bspcore)/start.S -o ./gen_lib/start.o
	@riscv$(XLEN)-unknown-elf-gcc -march=$(MARCH) -mabi=$(MABI) $(DC) -mcmodel=medany -static -std=gnu99 -fno-common -fno-builtin-printf -D__ASSEMBLY__=1 -I$(bspinc) -c $(bspcore)/trap.S -o ./gen_lib/trap.o
	@riscv$(XLEN)-unknown-elf-gcc -march=$(MARCH) -mabi=$(MABI) $(DC) -mcmodel=medany -static -std=gnu99 -fno-common -fno-builtin-printf -I$(bspinc) -I$(bspboard) -c $(bsplib)/printf.c -o ./gen_lib/printf.shakti
	@riscv$(XLEN)-unknown-elf-gcc -march=$(MARCH) -mabi=$(MABI) $(DC) -mcmodel=medany -static -std=gnu99 -fno-builtin-printf -I$(bspinc) -I$(bspboard) -c $(bsplib)/log.c -o ./gen_lib/log.o -lm -lgcc
	@riscv$(XLEN)-unknown-elf-gcc -march=$(MARCH) -mabi=$(MABI) $(DC) -mcmodel=medany -static -std=gnu99 -fno-builtin-printf -I$(bspinc) -I$(bspboard) -I$(bspdri)/plic -c $(bspcore)/init.c -o ./gen_lib/init.o -lm -lgcc
	@riscv$(XLEN)-unknown-elf-gcc -march=$(MARCH) -mabi=$(MABI) $(DC) -mcmodel=medany -static -std=gnu99 -fno-builtin-printf -I$(bspinc) -I$(bspboard) -c $(bspdri)/plic/plic_driver.c -o ./gen_lib/plic_driver.o -lm -lgcc
	@riscv$(XLEN)-unknown-elf-gcc -march=$(MARCH) -mabi=$(MABI) $(DC) -mcmodel=medany -static -std=gnu99 -fno-builtin-printf -I$(bspinc) -I$(bspboard) -c $(bspdri)/clint/clint_driver.c -o ./gen_lib/clint_driver.o -lm -lgcc
	@riscv$(XLEN)-unknown-elf-gcc -march=$(MARCH) -mabi=$(MABI) $(DC) -mcmodel=medany -static -std=gnu99 -fno-builtin-printf -I$(bspinc) -I$(bspboard) -I$(bspinc)/ethernet -c $(bspdri)/ethernet/eth_driver.c -o ./gen_lib/eth_driver.o -lm -lgcc
build:
	@riscv$(XLEN)-unknown-elf-ar rcs ./gen_lib/libshakti$(XLEN).a ./gen_lib/start.o ./gen_lib/trap.o ./gen_lib/util.o ./gen_lib/traps.o ./gen_lib/log.o ./gen_lib/printf.shakti ./gen_lib/qspi_micron.o ./gen_lib/uart.o ./gen_lib/i2c_driver.o ./gen_lib/clint_driver.o ./gen_lib/plic_driver.o ./gen_lib/init.o  ./gen_lib/xadc_driver.o ./gen_lib/pwm_driver.o ./gen_lib/eth_driver.o

do:
ifeq ($(PROGRAM),ALU)
	@$(eval filepath := ./ALU)
else
ifeq ($(PROGRAM),ALUrand)
	@$(eval filepath := ./ALUrand)
else
ifeq ($(PROGRAM),Arrays)
	@$(eval filepath := ./Arrays)
else
ifeq ($(PROGRAM),Arrays2)
	@$(eval filepath := ./Arrays2)
else
ifeq ($(PROGRAM),mkt)
	@$(eval filepath := ./mkt)
else
ifeq ($(PROGRAM),paranoia)
	@$(eval filepath := ./paranoia)
else
	@echo "Entry for $(PROGRAM) not present"
endif
endif
endif
endif
endif
endif

.PHONY: run_gdb
run_gdb: library do
	@echo "Starting OpenOCD and running $(PROGRAM) on RAM using GDB..."
	@echo $(openocd)
	@cd $(shell pwd)/../../bsp/third_party/artix7_100t && $(openocd) -f ftdi.cfg & 
	@sleep 2  # wait for OpenOCD to initialize
	@riscv-none-elf-gdb -ex "set remotetimeout unlimited" \
	                              -ex "target remote localhost:3333" \
	                              -ex "file $(GENLIB)$(PROGRAM)/output/$(PROGRAM).shakti" \
	                              -ex "load" \
	                              -ex "c"

finish:
	@if [ "$(PROGRAM)" = "all" ]; then \
		echo "make all over"; \
	else \
		cd $(filepath) && $(MAKE) $(PROGRAM).riscv TARGET=$(TARGET) DEBUG=$(DEBUG); \
	fi
