NOSEFART=/home/me/nes/nosefart-2.9-mls/nsfobj/build/nsfinfo.o \
/home/me/nes/nosefart-2.9-mls/nsfobj/build/cpu/nes6502/dis6502.o \
/home/me/nes/nosefart-2.9-mls/nsfobj/build/cpu/nes6502/nes6502.o \
/home/me/nes/nosefart-2.9-mls/nsfobj/build/log.o \
/home/me/nes/nosefart-2.9-mls/nsfobj/build/machine/nsf.o \
/home/me/nes/nosefart-2.9-mls/nsfobj/build/sndhrdw/vrc7_snd.o \
/home/me/nes/nosefart-2.9-mls/nsfobj/build/sndhrdw/fds_snd.o \
/home/me/nes/nosefart-2.9-mls/nsfobj/build/sndhrdw/fmopl.o \
/home/me/nes/nosefart-2.9-mls/nsfobj/build/sndhrdw/mmc5_snd.o \
/home/me/nes/nosefart-2.9-mls/nsfobj/build/sndhrdw/vrcvisnd.o \
/home/me/nes/nosefart-2.9-mls/nsfobj/build/sndhrdw/nes_apu.o \
/home/me/nes/nosefart-2.9-mls/nsfobj/build/memguard.o

all:
	dmdi -g -J. nsf.d $(NOSEFART)
