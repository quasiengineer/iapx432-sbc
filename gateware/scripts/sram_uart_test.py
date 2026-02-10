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

# How many addresses to test? (Max 65536)
# Set to 65536 for full check, or e.g., 1000 for a quick check.
TEST_SIZE = 65536

def main():
    if TEST_SIZE > 65536 or TEST_SIZE <= 0:
        print("Error: TEST_SIZE must be between 1 and 65536.")
        sys.exit(1)

    try:
        ser = serial.Serial(PORT, BAUD_RATE, timeout=TIMEOUT)
        print(f"Connected to {PORT} at {BAUD_RATE} baud.")
    except serial.SerialException as e:
        print(f"Error opening serial port: {e}")
        sys.exit(1)

    try:
        # ------------------------------------------------------------------
        # 1. Heartbeat Check & Suppression
        # ------------------------------------------------------------------
        print("\n--- Checking for Heartbeat (0xAA) ---")
        print("Listening for up to 2 seconds...")

        heartbeat_disabled = False
        start_time = time.time()

        while heartbeat_disabled == False:
          heartbeat_detected = False
          while time.time() - start_time < 2.0:
              if ser.in_waiting > 0:
                  byte = ser.read(1)
                  if byte == b'\xAA':
                      print("Heartbeat (0xAA) detected.")
                      heartbeat_detected = True
                      break
              else:
                  time.sleep(0.01)

          if heartbeat_detected:
              print("Sending Cmd 0x01 to toggle (disable) heartbeat...")
              ser.write(b'\x01')
              ser.reset_input_buffer()
          else:
              print("No heartbeat detected. Assuming it is already disabled.")
              heartbeat_disabled = True

        # ------------------------------------------------------------------
        # 2. Ping Test (Sanity Check)
        # ------------------------------------------------------------------
        print("\n--- Step 2: Ping Test (Cmd 0x04) ---")
        ser.reset_input_buffer()
        ser.write(b'\x04')

        response = ser.read(1)

        if response == b'\xEE':
            print("SUCCESS: Ping replied with 0xEE. FPGA is responsive.")
        else:
            print(f"FAILURE: Ping expected 0xEE, got {response.hex() if response else 'Timeout'}.")
            print("Aborting test.")
            sys.exit(1)

        # ------------------------------------------------------------------
        # 3. Memory Test (Write Phase)
        # ------------------------------------------------------------------
        print(f"\n--- Step 3: Write Test ({TEST_SIZE} addresses) ---")

        # Select unique random addresses if size < 65536
        # This gives better coverage than just testing 0..N
        if TEST_SIZE == 65536:
            addresses = list(range(65536))
            print("Generating full 64K address list and shuffling...")
        else:
            print(f"Picking {TEST_SIZE} random unique addresses from 64K space...")
            addresses = random.sample(range(65536), TEST_SIZE)

        random.shuffle(addresses) # Shuffle write order

        # Calculate dynamic progress step (1% of total)
        progress_step = max(1, int(TEST_SIZE / 100))

        print("Writing data (Value = Address)...")

        for i, addr in enumerate(addresses):
            val = addr

            # Protocol: 0x02 <AH> <AL> <DH> <DL> -> Expects 0xAC Ack
            packet = struct.pack('>BHH', 0x02, addr, val)
            ser.write(packet)

            response = ser.read(1)
            if response != b'\xAC':
                print(f"\nFATAL: Write failed at Addr 0x{addr:04X}. Expected 0xAC, got {response.hex()}")
                sys.exit(1)

            if (i + 1) % progress_step == 0 or (i + 1) == TEST_SIZE:
                percent = (i + 1) / TEST_SIZE * 100
                print(f"  [Write] {i+1}/{TEST_SIZE} words ({percent:.1f}%) complete...", end='\r')

        print(f"\nWrite phase complete.")

        # ------------------------------------------------------------------
        # 4. Memory Test (Read Verification Phase)
        # ------------------------------------------------------------------
        print("\n--- Step 4: Verification (Read Phase) ---")

        errors = 0

        for i, addr in enumerate(addresses):
            expected_val = addr

            # Cmd 0x03 <AH> <AL> -> Expects 2 bytes back
            packet = struct.pack('>BH', 0x03, addr)
            ser.write(packet)

            response = ser.read(2)

            if len(response) != 2:
                print(f"\nError reading 0x{addr:04X}: Timeout or partial data ({response.hex()})")
                errors += 1
                continue

            read_val = struct.unpack('>H', response)[0]

            if read_val != expected_val:
                print(f"\nMISMATCH at 0x{addr:04X}: Expected 0x{expected_val:04X}, Got 0x{read_val:04X}")
                errors += 1
                if errors >= 10:
                    print("\nToo many errors. Aborting verification.")
                    break

            if (i + 1) % progress_step == 0 or (i + 1) == TEST_SIZE:
                percent = (i + 1) / TEST_SIZE * 100
                print(f"  [Verify] {i+1}/{TEST_SIZE} words ({percent:.1f}%) complete...", end='\r')

        # ------------------------------------------------------------------
        # Summary
        # ------------------------------------------------------------------
        print("\n\n" + "="*40)
        if errors == 0:
            print(f"TEST PASSED: {TEST_SIZE} locations verified successfully.")
        else:
            print(f"TEST FAILED: Found {errors} errors.")
        print("="*40)

    except KeyboardInterrupt:
        print("\nUser interrupted test.")
    finally:
        ser.close()
        print("Serial port closed.")

if __name__ == "__main__":
    main()