import { sbc_bulkWrite, sbc_openPort, sbc_ping, sbc_closePort, sbc_startGdp, sbc_readLog, sbc_readRAM } from './sbc.js';
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
  console.log('Connected to SBC');

  await sbc_waitOnline();
  console.log('SBC is online');

  const { image, segments } = buildImage();
  await sbc_bulkWrite(image);
  console.log(`ROM image has been written to SBC, size = ${image.length} bytes`);

  await sbc_startGdp();
  console.log('GDP has been started');

  // wait some time to let GDP work
  await new Promise(resolve => setTimeout(resolve, 2000));

  const startAddr = parseInt(args['--log-skip']) || 0;
  console.log(`Access log (skipped ${startAddr} entries):`);
  for (let logAddr = startAddr; logAddr < (1 << 10); logAddr++) {
    const response = await sbc_readLog(logAddr);
    const accessAddr = (response[0] << 8) | response[1];
    const spec = response[2];
    if (printAccessLogEntry(logAddr, spec, accessAddr, segments)) {
      break;
    }
  }

  // fault info area starts at +0x40 in Processor data segment, fault status is 7th word (starting from 0)
  // const faultCodeRaw = await sbc_readRAM(segments.processorData + 0x40 + 14);
  // const faultCode = faultCodeRaw[0] << 8 | faultCodeRaw[1];
  // console.log(`Fault code: ${toHex(faultCode)}`);

  // print whole fault info area
  // for (let addr = segments.processorData + 0x40; addr < segments.processorData + 0x68; addr += 2) {
  //   const data = await sbc_readRAM(addr);
  //   console.log(`${toHex(addr)}: ${toHex(data[0] << 8 | data[1])}`);
  // }
};

main()
.catch(console.error)
.finally(() => sbc_closePort());
