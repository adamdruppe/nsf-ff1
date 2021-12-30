# this is driven by the top level makefile that sets some args

NOSEFART_SRC= \
nsfinfo.c \
cpu/nes6502/dis6502.c \
cpu/nes6502/nes6502.c \
log.c \
machine/nsf.c \
sndhrdw/vrc7_snd.c \
sndhrdw/fds_snd.c \
sndhrdw/fmopl.c \
sndhrdw/mmc5_snd.c \
sndhrdw/vrcvisnd.c \
sndhrdw/nes_apu.c \
memguard.c

# OEXT=o
# CC=gcc

OEXT=obj
CC=clang --target=x86_64-pc-windows-msvc

NOSEFART_OBJ=$(patsubst %.c, %.$(OEXT), $(NOSEFART_SRC))

%.$(OEXT): %.c $(NOSEFART_SRC)
	$(CC) -DNSF_PLAYER -ggdb -I. -Isndhrdw -Imachine -Icpu/nes6502 -DNES6502_MEM_ACCESS_CTRL -c -o $@ $<

all: $(NOSEFART_OBJ)
