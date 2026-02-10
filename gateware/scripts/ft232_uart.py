#!/usr/bin/env python3
from pyftdi.ftdi import Ftdi

# Reset FT232H to default mode (UART)
def reset_ft232h_to_default():
    ftdi = Ftdi()
    ftdi.open_from_url('ftdi://ftdi:232h/1')
    ftdi.set_bitmode(0, Ftdi.BitMode.RESET)
    ftdi.close()
    print("FT232H reset to default mode (UART)")

if __name__ == '__main__':
    reset_ft232h_to_default()