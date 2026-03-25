import { printAccessLogEntry, printHexDump, toHex, printFaultInfo } from './format.js';
import { buildImage } from './imageBuilder/image.js';
import {
  sbc_bulkWrite,
  sbc_openPort,
  sbc_waitFatal,
  sbc_ping,
  sbc_closePort,
  sbc_startGdp,
  sbc_readLog,
  sbc_readRAM,
  sbc_readWLog, WLOG_RECORD_COUNT,
} from './sbc.js';

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

const args = Object.fromEntries(process.argv.slice(2).map((arg) => arg.split('=')));

const printAccessLog = async (objects, vars) => {
  // read write log (operations to write data to memory)
  const writeLogRaw = await sbc_readWLog();
  const writeLog = [];
  const writeMap = new Map();
  for (let i = 0; i < WLOG_RECORD_COUNT; i += 4) {
    const writeData = writeLogRaw[i + 0] << 8 | writeLogRaw[i + 1];
    const writeLocation = writeLogRaw[i + 2] << 8 | writeLogRaw[i + 3];
    const logRef = writeLocation & 0x1FFF;
    const writeOffset = writeLocation >> 13;
    writeLog.push({ accessLogRef: logRef, data: writeData, writeOffset });
  }

  for (const { accessLogRef, data, writeOffset } of writeLog) {
    if (!writeMap.has(accessLogRef)) {
      writeMap.set(accessLogRef, []);
    }
    writeMap.get(accessLogRef).push({ data, writeOffset });
  }

  // read access log (any operations on the bus)
  const startAddr = parseInt(args['--log-skip']) || 0;
  const processDataFaultArea = objects.find(obj => obj.ref === 'processData').address + 0x68;
  console.log(`[+] Access log (skipped ${startAddr} entries):`);
  for (let logAddr = startAddr; logAddr < (1 << 12); logAddr++) {
    const response = await sbc_readLog(logAddr);
    const accessAddr = (response[0] << 8) | response[1];
    const spec = response[2];
    if (spec === 0x00 && accessAddr === 0x0000) {
      break;
    }

    // fault occured, not so interested to print the rest of the log
    if ((spec & 0b1100_0000) === 0b0100_0000 && accessAddr >= processDataFaultArea && accessAddr <= processDataFaultArea + 0x24) {
      break;
    }

    printAccessLogEntry(logAddr, spec, accessAddr, objects, writeMap, vars);
    if (spec === 0xF0) {
      break;
    }
  }
};

const printFault = async (objects, instructionsMap) => {
  const processDataFaultArea = objects.find(obj => obj.ref === 'processData').address + 0x68;
  const faultInfo = [];

  for (let address = processDataFaultArea; address <= processDataFaultArea + 0x28; address += 2) {
    const faultAreaWord = await sbc_readRAM(address);
    faultInfo[(address - processDataFaultArea) >> 1] = faultAreaWord[1] | (faultAreaWord[0] << 8);
  }

  printFaultInfo(faultInfo, instructionsMap);
};

const main = async () => {
  const programName = args['--program'] || 'dummy';

  if (args.hasOwnProperty('--print-image')) {
    const { image } = buildImage(programName);
    console.log(`RAM Image dump:`);
    printHexDump(image);
    return;
  }

  let writeIdx = 0;
  await sbc_openPort(
    (addr, data) => {
      writeIdx++;
      console.log(`[!] Interconnect space write from i432 <${String(writeIdx).padStart(4, '0')}>: addr=${toHex(addr)}, data=${toHex(data)}`);
    },
    (data, ticks) => console.log(`[!] Write to special address 0x1000: data=${toHex(data)}, ticks=${ticks}, host ts = ${Date.now()}`),
  );

  console.log('[+] Connected to SBC');

  await sbc_waitOnline();
  console.log('[+] SBC is online');

  console.log('[~] Building image...');
  const { image, objects, instructionsMap, vars } = buildImage(programName);
  await sbc_bulkWrite(image);
  console.log(`[+] ROM image has been written to SBC, size = ${image.length} bytes`);

  await sbc_startGdp();
  console.log('[+] GDP has been started');

  await sbc_waitFatal();
  console.log('[!] GDP has stopped');

  if (args.hasOwnProperty('--print-log')) {
    console.log('[~] Read access log after 2s of execution.');
    await printAccessLog(objects, vars);
  }

  await printFault(objects, instructionsMap);
};

main()
.catch(console.error)
.finally(() => sbc_closePort());
