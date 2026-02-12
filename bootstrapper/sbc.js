import EventEmitter from 'node:events';
import { SerialPort } from 'serialport'

const PORT_NAME = '/dev/ttyUSB0';
const BAUD_RATE = 115200;
const RESPONSE_TIMEOUT_IN_MS = 1000; // 1s

const COMMANDS = {
  PING: 0x80,
  START_GDP: 0x81,
  SRAM_BULK_WRITE: 0x01,
  SRAM_READ: 0x03,
  LOG_READ: 0x11,
};

const ACK_REPLY = 0x01;

const eventBus = new EventEmitter();
const port = new SerialPort({ path: PORT_NAME, baudRate: BAUD_RATE, autoOpen: false });

const responseBuffer = {
  remaining: 0,
  result: [],
};

port.on('data', async (data) => {
  const { remaining, result} = responseBuffer;

  if (remaining) {
    // wait for more data
    if (remaining >= data.length) {
      result.push(...data);
      responseBuffer.remaining -= data.length;
      return;
    }

    if (data.length != remaining + 1) {
      throw new Error('Unexpected data size');
    }

    result.push(...data.subarray(0, remaining));
    responseBuffer.remaining = 0;
    if (data[remaining] !== ACK_REPLY) {
      throw new Error('Expected ACK byte');
    }
  } else {
    if (data.length !== 1 || data[0] !== ACK_REPLY) {
      throw new Error('Expected only ACK byte');
    }
  }

  eventBus.emit('ack');
});


const sendCommand = (
  port,
  { opcode, data, timeout = RESPONSE_TIMEOUT_IN_MS, expectedRespone = 0 },
) => new Promise((resolve, reject) => {
  let timeoutId = null;

  responseBuffer.result = [];
  responseBuffer.remaining = expectedRespone;

  eventBus.once('ack', () => {
    if (timeoutId) {
      clearTimeout(timeoutId);
    }

    resolve(responseBuffer.result);
  });

  port.write(Buffer.from([opcode, ...(data ?? [])]), (err) => err && reject(err));

  if (timeout) {
    // don't wait too long for a response
    timeoutId = setTimeout(() => reject(new Error('Timeout')), timeout);
  }
});

export async function sbc_ping() {
  return sendCommand(port, { opcode: COMMANDS.PING });
};

export async function sbc_startGdp() {
  return sendCommand(port, { opcode: COMMANDS.START_GDP });
};

export async function sbc_readLog(addr) {
  return sendCommand(port, { opcode: COMMANDS.LOG_READ, data: [addr >> 8, addr & 0xFF], expectedRespone: 3 });
};

export async function sbc_readRAM(addr) {
  return sendCommand(port, { opcode: COMMANDS.SRAM_READ, data: [addr >> 8, addr & 0xFF], expectedRespone: 2 });
};

export async function sbc_bulkWrite(data) {
  const sz = data.length / 2;
  const writes = [];
  for (let i = sz - 1; i >= 0; i--) {
    writes.push(data[i * 2 + 1], data[i * 2]);
  }

  return sendCommand(port, { opcode: COMMANDS.SRAM_BULK_WRITE, data: [sz >> 8, sz & 0xFF, ...writes], timeout: null });
};

export async function sbc_openPort() {
  return new Promise((resolve, reject) => {
    port.open((err) => {
      if (err) {
        reject(err);
      } else {
        resolve();
      }
    });
  });
};

export function sbc_closePort() {
  port.close();
};