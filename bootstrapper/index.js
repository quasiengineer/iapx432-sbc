import { sbc_bulkWrite, sbc_openPort, sbc_ping, sbc_closePort, sbc_startGdp, sbc_readLog, sbc_readRAM, sbc_readWLog } from './sbc.js';
import { printAccessLogEntry, printHexDump, toHex } from './format.js';
import { buildImage } from './imageBuilder/image.js';

const PING_RETRIES = 5;

/*
 * Wait for the SBC to respond to ping requests
 */
const sbc_waitOnline = async () => {
  for (let i = 0; i < PING_RETRIES; i++) {
    try {
      await sbc_ping();
      return;
    } catch (e) {
      // ignore
    }
  }

  throw new Error('SBC not responding');
};

const args = process.argv.slice(2).reduce((acc, k, i, arr) => i % 2 === 0 ? {...acc, [k]: arr[i + 1]} : acc, {});

const printAccessLog = async (objects) => {
  // read write log (operations to write data to memory)
  const writeLogRaw = await sbc_readWLog();
  const writeLog = [];
  const writeMap = new Map();
  for (let i = 0; i < 256; i += 4) {
    const writeData = writeLogRaw[i + 0] << 8 | writeLogRaw[i + 1];
    const writeLocation = writeLogRaw[i + 2] << 8 | writeLogRaw[i + 3];
    const logRef = writeLocation & 0x3FF;
    const writeOffset = writeLocation >> 10;
    writeLog.push({ accessLogRef: logRef, data: writeData, writeOffset });
  }

  for (const { accessLogRef, data, writeOffset } of writeLog) {
    if (!writeMap.has(accessLogRef)) {
      writeMap.set(accessLogRef, []);
    }
    writeMap.get(accessLogRef).push({ data: toHex(data, 4, true), writeOffset });
  }

  // read access log (any operations on the bus)
  const startAddr = parseInt(args['--log-skip']) || 0;
  console.log(`[+] Access log (skipped ${startAddr} entries):`);
  for (let logAddr = startAddr; logAddr < (1 << 10); logAddr++) {
    const response = await sbc_readLog(logAddr);
    const accessAddr = (response[0] << 8) | response[1];
    const spec = response[2];
    if (spec === 0x00 && accessAddr === 0x0000) {
      break;
    }

    printAccessLogEntry(logAddr, spec, accessAddr, objects, writeMap);
    if (spec === 0xF0) {
      break;
    }
  }
};

const main = async () => {
  if (args.hasOwnProperty('--print-image')) {
    const { image, segments } = buildImage();
    console.log(`RAM Image dump:`);
    printHexDump(image);
    console.log(`Segments:`);
    console.log(segments);
    return;
  }

  await sbc_openPort();
  console.log('[+] Connected to SBC');

  await sbc_waitOnline();
  console.log('[+] SBC is online');

  console.log('[~] Building image...');
  const { image, objects } = buildImage();
  await sbc_bulkWrite(image);
  console.log(`[+] ROM image has been written to SBC, size = ${image.length} bytes`);

  await sbc_startGdp({ localCommsAddress: objects.find(({ ref }) => ref === 'processorLocalComms').address });
  console.log('[+] GDP has been started');

  // wait some time to let GDP work
  await new Promise(resolve => setTimeout(resolve, 2000));

  console.log('[~] Read access log after 2s of execution.');
  await printAccessLog(objects);
};

main()
.catch(console.error)
.finally(() => sbc_closePort());
