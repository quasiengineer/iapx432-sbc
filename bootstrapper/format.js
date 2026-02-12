const toHex = (value, sz = 4) => value.toString(16).padStart(sz, '0');

const printAccessLogEntry = (logAddr, spec, accessAddr) => {
  const spaceType = (spec >> 7) & 1;
  const operation = (spec >> 6) & 1;
  const rmw = (spec >> 5) & 1;
  const lengthCode = (spec >> 2) & 7;
  const modifier = spec & 3;

  // it is not valid combination, so it comes from FPGA logic
  if (spaceType === 1 && modifier !== 3) {
    const fpgaLogMap = {
      0xf4: 'GDP initialization',
      0xf0: 'Fatal signal is raised by GDP',
    };
    console.log(`  0x${toHex(logAddr)}: ${fpgaLogMap[spec] || 'Unknown FPGA log entry'}`);
    return spec === 0xf0;
  }

  const lengthMap = {0: 1, 1: 2, 2: 4, 3: 6, 4: 8, 5: 10};
  const length = lengthMap[lengthCode] || 'invalid';

  const spaceStr = spaceType === 1 ? 'Other' : 'Memory';
  const opStr = operation === 0 ? 'read' : 'write';
  const rmwStr = rmw ? ', RMW' : '';

  let segStr;
  if (spaceType === 1) {
    segStr = 'interconnect register';
  } else {
    const segMap = {0: 'instruction segment', 1: 'stack segment', 2: 'context control segment', 3: 'other'};
    segStr = segMap[modifier] || 'invalid';
  }

  console.log(`  0x${toHex(logAddr)}: spec=0x${toHex(spec, 2)} (${opStr} ${length} bytes in '${spaceStr}' space with ${segStr} access${rmwStr}) addr=0x${toHex(accessAddr)}`);
  return false;
};

export {
  printAccessLogEntry,
  toHex,
};