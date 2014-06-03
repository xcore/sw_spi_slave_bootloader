SPI slave bootloader
....................

:Stable release: unreleased

:Status: Experimental

:Maintainer: https://github.com/rlsosborne

:Description: SPI slave bootloader

Key Features
============

* SPI slave bootloader for booting the xCORE from another device (e.g. another
  microcontroller).

Description
===========

This bootloader implements a SPI slave device that waits to receive a bootable
image over a SPI interface. On receipt of a valid image the bootloader copies
the image to the start of RAM and jumps to the start of the image. The bootloader
itself must be loaded via one of the boot methods supported natively by the
xCORE, for example it could be written to the xCORE's OTP or it could be loaded
from the start of a SPI flash.

The bootloader accepts a single binary image which is loaded to the RAM of the
tile the bootloader is running on. It is the loaded image's responsibility to
setup the xCONNECT network / distribute code to other tiles if required.

Support
=======

Issues may be submitted via the 'Issues' tab of the github repository
