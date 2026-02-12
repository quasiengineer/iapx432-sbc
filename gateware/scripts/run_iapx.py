import serial
import struct
import random
import time
import sys

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------
PORT = '/dev/ttyUSB0'
BAUD_RATE = 115200
TIMEOUT = 3.0  # Serial timeout in seconds

def print_log_entry(log_addr, spec, access_addr):
    # Extract fields from spec
    space = (spec >> 7) & 1
    operation = (spec >> 6) & 1
    rmw = (spec >> 5) & 1
    length_code = (spec >> 2) & 7
    modifier = spec & 3

    # it is not valid combination, so it comes from FPGA logic
    if space == 1 and modifier != 3:
        fpga_log_map = {
            0xf4: "GDP initialization",
            0xf0: "Fatal signal is raised by GDP",
        }
        print(f"0x{log_addr:04X}: {fpga_log_map.get(spec, 'Unknown FPGA log entry')}")
        return spec == 0xf0


    # Map length
    length_map = {0: 1, 1: 2, 2: 4, 3: 6, 4: 8, 5: 10}
    length = length_map.get(length_code, "invalid")

    # Strings
    space_str = "Other" if space else "Memory"
    op_str = "read" if operation == 0 else "write"
    rmw_str = ", RMW" if rmw else ""

    if space:
        seg_str = "interconnect register"
    else:
        seg_map = {0: "instruction segment", 1: "stack segment", 2: "context control segment", 3: "other"}
        seg_str = seg_map.get(modifier, "invalid")

    # Pretty print
    print(f"0x{log_addr:04X}: spec=0x{spec:02X} ({op_str} {length} bytes in \"{space_str}\" space with {seg_str} access{rmw_str}) addr=0x{access_addr:04X}")
    return False

def main():
    try:
        ser = serial.Serial(PORT, BAUD_RATE, timeout=TIMEOUT)
        print(f"Connected to {PORT} at {BAUD_RATE} baud.")
    except serial.SerialException as e:
        print(f"Error opening serial port: {e}")
        sys.exit(1)

    try:
        ping_retries = 3
        successful_ping = False
        for _ in range(ping_retries):
            ser.reset_input_buffer()
            ser.write(b'\x80')
            response = ser.read(1)
            if response == b'\x01':
                print("SUCCESS: Ping successful")
                successful_ping = True
                break


        if not successful_ping:
            print("FAILURE: Ping failed after {} retries".format(ping_retries))
            sys.exit(1)

        # send GDP start command
        ser.write(b'\x81')
        response = ser.read(1)
        if response != b'\x01':
            print("FAILURE: GDP start command failed")
            sys.exit(1)

        # wait a bit
        print("Waiting 3s for GDP to execute...")
        time.sleep(3)

        # read log
        for log_addr in range(1 << 10):
            # Cmd 0x11 <AH> <AL> -> Expects 4 bytes back
            packet = struct.pack('>BH', 0x11, log_addr)
            ser.write(packet)
            response = ser.read(4)
            if len(response) != 4:
                print(f"\nError reading 0x{log_addr:04X}: Timeout or partial data ({response.hex()})")
                sys.exit(1)

            access_addr, spec, ack_op = struct.unpack('>BHBB', response)
            if ack_op != 0x01:
                print(f"\nError reading 0x{log_addr:04X}: response = {response.hex()}")
                sys.exit(1)

            if print_log_entry(log_addr, spec, access_addr):
                break


    except KeyboardInterrupt:
        print("\nUser interrupted test.")
    finally:
        ser.close()
        print("Serial port closed.")


if __name__ == "__main__":
    main()
