const toHex = (value, sz = 4, raw = false) => raw ? value.toString(16).padStart(sz, '0') : `0x${value.toString(16).padStart(sz, '0')}`;

const FPGA_LOG_MAP = {
  0xf4: 'GDP initialization',
  0xf0: 'Fatal signal is raised by GDP',
};

const MEMORY_ACCESS_MODIFIER_MAP = [
  'instruction segment',
  'stack segment',
  'context control segment',
  'other',
];

const lookupAddress = (accessAddr, accessType, segments) => {
  // interconnect register
  if (accessType === 1) {
    return toHex(accessAddr);
  }

  const segment = segments.find(({ address, size }) => accessAddr >= address && accessAddr < address + size);
  return segment ? `${segment.ref}+${toHex(accessAddr - segment.address, 2)} (${toHex(accessAddr)})` : toHex(accessAddr);
};

const printAccessLogEntry = (logAddr, spec, accessAddr, segments, writesMap) => {
  const accessType = (spec >> 7) & 1;
  const operation = (spec >> 6) & 1;
  const rmw = (spec >> 5) & 1;
  const lengthCode = (spec >> 2) & 7;
  const modifier = spec & 3;

  // it is not valid combination, so it comes from FPGA logic
  if (accessType === 1 && modifier !== 3) {
    console.log(`  [${logAddr.toString().padStart(4, '0')}] ${FPGA_LOG_MAP[spec] || 'Unknown FPGA log entry'}`);
    return;
  }

  const lengthMap = { 0: 1, 1: 2, 2: 4, 3: 6, 4: 8, 5: 10 };
  const length = lengthMap[lengthCode] || 'XX';

  const accessStr = accessType === 1 ? 'Other' : 'Memory';
  const opStr = operation === 0 ? 'RD' : 'WR';
  const rmwStr = rmw ? ', RMW' : '';
  const modifierStr = accessType === 1 ? 'interconnect register' : (MEMORY_ACCESS_MODIFIER_MAP[modifier] || 'invalid');

  const writeData = writesMap.has(logAddr) ? writesMap.get(logAddr) : [];
  const formattedWriteData = writeData.sort((a, b) => b.writeOffset - a.writeOffset).map(({ data }) => data).join(' ') || 'unknown';
  console.log(`  [${logAddr.toString().padStart(4, '0')}] spec: ${toHex(spec, 2)} (${opStr} ${length}b, '${accessStr}/${modifierStr}' access${rmwStr}) addr: ${lookupAddress(accessAddr, accessType, segments)}${operation === 0 ? '' : ` <${formattedWriteData}>`}`);
};

const printHexDump = (image) => {
  for (let i = 0; i < image.length; i += 16) {
    let line = '';
    for (let j = 0; j < 16 && (i + j) < image.length; j++) {
      line += toHex(image[i + j], 2, true) + ' ';
    }
    console.log(toHex(i, 4, true) + ': ' + line);
  }
}

export {
  printHexDump,
  printAccessLogEntry,
  toHex,
};