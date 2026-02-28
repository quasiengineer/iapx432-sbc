#!/usr/bin/env bash

sudo modprobe -r ftdi_sio
sudo modprobe ftdi_sio

echo "FT232H reset to default mode (UART)"