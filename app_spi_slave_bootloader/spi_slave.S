// Simple SPI slave bootloader.
//
// The xCORE waits to be sent a bootable image. The SPI master should select the
// xCORE by driving the slave select low and then send an image in the following
// format:
// - Image size in words
// - Image data
// - Image CRC
//
// Each byte is transmitted least significant bit first. The CRC is calculated
// over the byte stream represented by the program size and the program itself.
// The polynomial used is 0xEDB88320 (IEEE 802.3). The CRC register is
// initialised with 0xFFFFFFFF and the residue is inverted to produce the CRC.
// The CRC check can be disabled by setting the CRC to 0x0D15AB1E.
//
// The received image is copied to the start of RAM. If the image CRC is valid
// the bootloader jumps to the start of the image, otherwise it waits to
// receive another image.

#define SPI_SS_PORT   XS1_PORT_1H
#define SPI_SCLK_PORT XS1_PORT_1K
#define SPI_MOSI_PORT XS1_PORT_1N

#include <xs1.h>

.set bootloader_bytes, _edp.bss - _start
.set bootloader_words, (bootloader_bytes + 3) / 4
.set bootloader_src, _start
.set bootloader_dest, .ram_base + .ram_size - (XS1_DBG_BUFFER_WORDS * 4  + bootloader_words * 4)
.set bootloader_offset, bootloader_dest - bootloader_src

// Relocate to the end of memory.
.text
.globl _start
_start:
  ldap r11, bootloader_src
  mov r0, r11
  ldap r11, bootloader_dest
  ldc r1, bootloader_words
relocation_loop:
  sub r1, r1, 1
  ldw r2, r0[r1]
  stw r2, r11[r1]
  bt r1, relocation_loop
  // Jump to the code now at the end of memory.
.set relocation_jump_dest, after_relocation + bootloader_offset
  bu relocation_jump_dest

after_relocation:

  clre
  // Setup dp
  ldap r11, _dp
  set dp, r11
  // Setup vector base (needed to use events)
  ldw r11, dp[ramBase]
  ldc r2, XS1_PS_VECTOR_BASE
  set ps[r2], r11

#define BITREV_POLY 0xedb88320

.section .dp.data, "awd", @progbits
.align 4
ss_port:
.word SPI_SS_PORT      // SS
sclk_port:
.word SPI_SCLK_PORT    // SCLK
mosi_port:
.word SPI_MOSI_PORT    // MOSI
bitrev_poly:
.word BITREV_POLY      // Poly
crc_disable_magic:
.word 0xd15ab1e
ramBase:
.word .ram_base

#define SCLK_REG r0
#define SS_REG r1
#define CLK1_REG r2
#define MOSI_REG r3
#define MEMBASE_REG r4
#define RECEIVE_REG r5
#define POLY_REG r6
#define CRC_REG r7
#define SIZE_REG r8

.text

  // Turn on and start clock block 0
  ldc r11, XS1_CLKBLK_REF
  setc res[r11], XS1_SETC_INUSE_ON
  setc res[r11], XS1_SETC_RUN_STARTR

  // SCLK
  ldw SCLK_REG, dp[sclk_port]
  setc res[SCLK_REG], XS1_SETC_INUSE_ON

  // SS
  ldw SS_REG, dp[ss_port]
  setc res[SS_REG], XS1_SETC_INUSE_ON
  setc res[SS_REG], XS1_SETC_INV_INVERT

  // Turn on the clock block 1
  ldc CLK1_REG, XS1_CLKBLK_1
  setc res[CLK1_REG], XS1_SETC_INUSE_ON

  // Configure clock block 1
  setclk res[CLK1_REG], SCLK_REG
  setrdy res[CLK1_REG], SS_REG

  // MOSI
  ldw MOSI_REG, dp[mosi_port]
  setc res[MOSI_REG], XS1_SETC_INUSE_ON
  setc res[MOSI_REG], XS1_SETC_BUF_BUFFERS
  setc res[MOSI_REG], XS1_SETC_RDY_STROBED
  setc res[MOSI_REG], XS1_SETC_MS_SLAVE
  ldc r11, 32
  settw res[MOSI_REG], r11
  setclk res[MOSI_REG], CLK1_REG

  // Setup events / conditions
  ldap r11, _SpiSlaveFail
  setv res[SS_REG], r11
  setc res[SS_REG], XS1_SETC_COND_EQ
  eeu res[SS_REG]

  eeu res[MOSI_REG]

  ldw POLY_REG, dp[bitrev_poly]

  // Start clock block 1
  setc res[CLK1_REG], XS1_SETC_RUN_STARTR

  // If SS goes low before we have recieved a valid image then jump to
  // _SpiSlaveStart in order to try again. Note that if there is a word of data
  // available and SS goes low then we will take the event on MOSI first due to
  // MOSI being buffered and having a higher resource ID. Therefore we only take
  // the SS event if there is less than a word stored in the buffers of MOSI in
  // which case we know we haven't received a valid image since the bootable
  // image must be a whole number of words.
_SpiSlaveFail:
_SpiSlaveStart:
  ldap r11, _SpiSlaveSize
  setv res[MOSI_REG], r11
  mkmsk CRC_REG, 32

  ldw MEMBASE_REG, dp[ramBase]
  // Wait for SS to go high (note SS is inverted).
  ldc r11, 0
  setd res[SS_REG], r11
  in r11, res[SS_REG]

  // Clear buffers.
  setc res[MOSI_REG], XS1_SETC_RUN_CLRBUF

  // Wait for SS to go low.
  ldc r11, 1
  setd res[SS_REG], r11
  in r11, res[SS_REG]

  // Setup condition for event.
  ldc r11, 0
  setd res[SS_REG], r11

  waiteu

_SpiSlaveSize:
  in SIZE_REG, res[MOSI_REG]
  crc32 CRC_REG, SIZE_REG, POLY_REG
  // For simplicity we treat the CRC as part of the data, i.e. it will be
  // written to RAM just like the rest of the image.
  add SIZE_REG, SIZE_REG, 1
  ldap r11, _SpiSlaveData
  setv res[MOSI_REG], r11
  waiteu

_SpiSlaveData:
  in RECEIVE_REG, res[MOSI_REG]
  crc32 CRC_REG, RECEIVE_REG, POLY_REG
  stw RECEIVE_REG, MEMBASE_REG[0]
  add MEMBASE_REG, MEMBASE_REG, 4
  sub SIZE_REG, SIZE_REG, 1
  bf SIZE_REG, _SpiSlaveCheckCrc
  waiteu

_SpiSlaveCheckCrc:
  ldw r11, dp[crc_disable_magic]
  eq r11, r11, RECEIVE_REG
  bt r11, _SpiSlaveSkipCrc

  not CRC_REG, CRC_REG
  bt CRC_REG, _SpiSlaveFail  // Try again in the case of failure.

_SpiSlaveSkipCrc:
  // Cleanup
  setc res[SS_REG], XS1_SETC_INUSE_OFF
  setc res[SCLK_REG], XS1_SETC_INUSE_OFF
  setc res[MOSI_REG], XS1_SETC_INUSE_OFF
  setc res[CLK1_REG], XS1_SETC_INUSE_OFF
  ldc r11, XS1_CLKBLK_REF
  setc res[r11], XS1_SETC_INUSE_OFF

  // Jump to the start of RAM.
  ldw r0, dp[ramBase]
  bla r0
