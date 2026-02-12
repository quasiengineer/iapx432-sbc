import { sbc_bulkWrite, sbc_openPort, sbc_ping, sbc_closePort, sbc_startGdp, sbc_readLog, sbc_readRAM } from './sbc.js';
import { printAccessLogEntry, toHex } from './format.js';
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

const main = async () => {
  await sbc_openPort();
  console.log('Connected to SBC');

  await sbc_waitOnline();
  console.log('SBC is online');

  const image = buildImage();
  await sbc_bulkWrite(image);
  console.log(`ROM image has been written to SBC, size = ${image.length} bytes`);

  // print hex dump of first 256 bytes
  console.log('First 256 bytes of image:');
  for (let i = 0; i < image.length; i += 16) {
    let line = '';
    for (let j = 0; j < 16 && (i + j) < image.length; j++) {
      line += toHex(image[i + j], 2) + ' ';
    }
    console.log(toHex(i, 4) + ': ' + line);
  }

  await sbc_startGdp();
  console.log('GDP has been started');

  // wait some time to let GDP work
  await new Promise(resolve => setTimeout(resolve, 1000));

  console.log('Access log:');
  for (let logAddr = 0; logAddr < (1 << 10); logAddr++) {
    const response = await sbc_readLog(logAddr);
    const accessAddr = (response[0] << 8) | response[1];
    const spec = response[2];
    if (printAccessLogEntry(logAddr, spec, accessAddr)) {
      break;
    }
  }
};

main()
.catch(console.error)
.finally(() => sbc_closePort());
