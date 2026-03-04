import EventEmitter from 'node:events';

const PORT_NAME = '/dev/ttyUSB0';
const BAUD_RATE = 2_000_000;
const RESPONSE_TIMEOUT_IN_MS = 1000; // 1s

const COMMANDS = {
  SRAM_BULK_WRITE: 0x01,
  SRAM_READ: 0x03,
  LOG_READ: 0x11,
  START_GDP: 0x81,
  PING: 0x80,
  WLOG_READ: 0x90,
};

const FPGA_OPCODES = {
  ACK: 0x01,
  I432_INTERCONNECT_WRITE: 0x02,
  I432_WRITE_WITH_TICKS: 0x03,
};

class SBC {
  #eventBus;
  #port;
  #buffer;
  #waitForResponse;
  #expectedResponseLength;

  constructor(SerialPort, onInterconnectWrite, onWriteWithTicks) {
    this.#eventBus = new EventEmitter();
    this.#port = new SerialPort({ path: PORT_NAME, baudRate: BAUD_RATE, autoOpen: false });
    this.#buffer = [];
    this.#waitForResponse = false;

    this.#port.on('data', (data) => {
      this.#buffer.push(...data);

      let bufferEvaluated = false;
      while (!bufferEvaluated) {
        bufferEvaluated = true;

        // Process response if waiting
        if (this.#waitForResponse && this.#buffer.length >= this.#expectedResponseLength + 1) {
          if (this.#buffer[this.#expectedResponseLength] !== FPGA_OPCODES.ACK) {
            throw new Error(`Expected ACK from FPGA, got ${this.#buffer[this.#expectedResponseLength]}`);
          }

          this.#waitForResponse = false;
          const response = this.#buffer.splice(0, this.#expectedResponseLength);
          this.#buffer.splice(0, 1); // remove ACK
          this.#eventBus.emit('ack', response);
          bufferEvaluated = false;
        }

        if (!this.#waitForResponse && this.#buffer.length > 0) {
          // Check for unknown opcode
          if (this.#buffer[0] !== FPGA_OPCODES.I432_INTERCONNECT_WRITE && this.#buffer[0] !== FPGA_OPCODES.I432_WRITE_WITH_TICKS) {
            throw new Error(`Unknown opcode from FPGA, code = ${this.#buffer[0]}`);
          }

          // Process target-initiated transfers
          while (this.#buffer.length >= 5 && this.#buffer[0] === FPGA_OPCODES.I432_INTERCONNECT_WRITE) {
            const msg = this.#buffer.splice(0, 5);
            onInterconnectWrite((msg[1] << 8) | msg[2], (msg[3] << 8) | msg[4]);
            bufferEvaluated = false;
          }

          while (this.#buffer.length >= 9 && this.#buffer[0] === FPGA_OPCODES.I432_WRITE_WITH_TICKS) {
            const msg = this.#buffer.splice(0, 9);
            const data = (msg[1] << 8) | msg[2];
            const ticks = (BigInt(msg[3]) << 40n) | (BigInt(msg[4]) << 32n) | (BigInt(msg[5]) << 24n) | (BigInt(msg[6]) << 16n) | (BigInt(msg[7]) << 8n) | BigInt(msg[8]);
            onWriteWithTicks(data, ticks);
            bufferEvaluated = false;
          }
        }
      }
    });
  }

  sendCommand({ opcode, data, timeout = RESPONSE_TIMEOUT_IN_MS, expectedRespone = 0 }) {
    return new Promise((resolve, reject) => {
      let timeoutId = null;

      this.#expectedResponseLength = expectedRespone;
      this.#waitForResponse = true;

      this.#eventBus.once('ack', (data) => {
        if (timeoutId) {
          clearTimeout(timeoutId);
        }

        resolve(data);
      });

      this.#port.write(Buffer.from([opcode, ...(data ?? [])]), (err) => err && reject(err));

      if (timeout) {
        // don't wait too long for a response
        timeoutId = setTimeout(() => reject(new Error('Timeout')), timeout);
      }
    });
  }

  open() {
    return new Promise((resolve, reject) => {
      this.#port.open((err) => {
        if (err) {
          reject(err);
        } else {
          resolve();
        }
      });
    });
  }

  close() {
    this.#port.close();
  }
}

let sbc;

export async function sbc_ping() {
  return sbc?.sendCommand({ opcode: COMMANDS.PING });
};

export async function sbc_startGdp() {
  return sbc?.sendCommand({ opcode: COMMANDS.START_GDP });
};

export async function sbc_readLog(addr) {
  return sbc?.sendCommand({ opcode: COMMANDS.LOG_READ, data: [addr >> 8, addr & 0xFF], expectedRespone: 3 });
};

export async function sbc_readRAM(addr) {
  return sbc?.sendCommand({ opcode: COMMANDS.SRAM_READ, data: [addr >> 8, addr & 0xFF], expectedRespone: 2 });
};

export const WLOG_RECORD_COUNT = (2 ** 7) * 4

export async function sbc_readWLog() {
  return sbc?.sendCommand({ opcode: COMMANDS.WLOG_READ, expectedRespone: WLOG_RECORD_COUNT });
}

export async function sbc_bulkWrite(data) {
  const writes = [];

  // SRAM keeps 16-bit words, so need to have padding
  if (data.length % 2 === 1) {
    writes.push(0x00, data[data.length - 1]);
  }

  for (let wordIdx = Math.floor(data.length / 2) - 1; wordIdx >= 0; wordIdx--) {
    writes.push(data[wordIdx * 2 + 1], data[wordIdx * 2]);
  }

  const wordsToWrite = writes.length >> 1;
  return sbc?.sendCommand({ opcode: COMMANDS.SRAM_BULK_WRITE, data: [wordsToWrite >> 8, wordsToWrite & 0xFF, ...writes], timeout: null });
};

export async function sbc_openPort(onInterconnectWrite, onWriteWithTicks) {
  // avoid initialization delays due regular import if we don't need to use the port
  const { SerialPort } = await import('serialport');
  sbc = new SBC(SerialPort, onInterconnectWrite, onWriteWithTicks);
  await sbc.open();
};

export function sbc_closePort() {
  sbc?.close();
};