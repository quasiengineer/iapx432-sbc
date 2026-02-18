import EventEmitter from 'node:events';

const PORT_NAME = '/dev/ttyUSB0';
const BAUD_RATE = 2_000_000;
const RESPONSE_TIMEOUT_IN_MS = 1000; // 1s

const COMMANDS = {
  SRAM_BULK_WRITE: 0x01,
  SRAM_READ: 0x03,
  LOG_READ: 0x11,
  START_GDP: 0x20,
  PING: 0x80,
  WLOG_READ: 0x90,
};

const ACK_REPLY = 0x01;

class SBC {
  #eventBus;
  #port;
  #responseBuffer;

  constructor(SerialPort) {
    this.#eventBus = new EventEmitter();
    this.#port = new SerialPort({ path: PORT_NAME, baudRate: BAUD_RATE, autoOpen: false });
    this.#responseBuffer = {
      remaining: 0,
      result: [],
    };

    this.#port.on('data', async (data) => {
      const { remaining, result } = this.#responseBuffer;

      if (remaining) {
        // wait for more data
        if (remaining >= data.length) {
          result.push(...data);
          this.#responseBuffer.remaining -= data.length;
          return;
        }

        if (data.length != remaining + 1) {
          throw new Error('Unexpected data size');
        }

        result.push(...data.subarray(0, remaining));
        this.#responseBuffer.remaining = 0;
        if (data[remaining] !== ACK_REPLY) {
          throw new Error('Expected ACK byte');
        }
      } else {
        if (data.length !== 1 || data[0] !== ACK_REPLY) {
          throw new Error('Expected only ACK byte');
        }
      }

      this.#eventBus.emit('ack');
    });
  }

  sendCommand({ opcode, data, timeout = RESPONSE_TIMEOUT_IN_MS, expectedRespone = 0 }) {
    return new Promise((resolve, reject) => {
      let timeoutId = null;

      this.#responseBuffer.result = [];
      this.#responseBuffer.remaining = expectedRespone;

      this.#eventBus.once('ack', () => {
        if (timeoutId) {
          clearTimeout(timeoutId);
        }

        resolve(this.#responseBuffer.result);
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

export async function sbc_startGdp({ localCommsAddress }) {
  return sbc?.sendCommand({
    opcode: COMMANDS.START_GDP,
    data: [localCommsAddress >> 8, localCommsAddress & 0xFF],
  });
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

export async function sbc_openPort() {
  // avoid initialization delays due regular import if we don't need to use the port
  const { SerialPort } = await import('serialport');
  sbc = new SBC(SerialPort);
  await sbc.open();
};

export function sbc_closePort() {
  sbc?.close();
};