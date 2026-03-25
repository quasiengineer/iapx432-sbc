import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { compile } from './compiler/compiler.js';
import { ObjectTableDirectory } from './storage/objectTableDirectory.js';
import { SEGMENT_TYPE } from './storage/objectTableDesciptors.js';
import { ObjectTable } from './storage/objectTable.js';
import { ProcessorAccessSegment } from './objects/processorAccessSegment.js';
import { ProcessorDataSegment } from './objects/processorDataSegment.js';
import { LocalCommunicationSegment } from './objects/localCommunicationSegment.js';
import { PortDataSegment, PORT_TYPE } from './objects/portDataSegment.js';
import { PortAccessSegment } from './objects/portAccessSegment.js';
import { CARRIER_TYPE, CarrierDataSegment } from './objects/carrierDataSegment.js';
import { CarrierAccessSegment } from './objects/carrierAccessSegment.js';
import { ProcessDataSegment } from './objects/processDataSegment.js';
import { ProcessAccessSegment } from './objects/processAccessSegment.js';
import { ContextDataSegment } from './objects/contextDataSegment.js';
import { ContextAccessSegment } from './objects/contextAccessSegment.js';
import { GenericDataSegment } from './objects/genericDataSegment.js';
import { DomainSegment } from './objects/domainSegment.js';
import { InstructionSegment } from './objects/instructionSegment.js';

const buildVarsSegmentContent = (vars) => {
  const data = [];
  for (const varName in vars) {
    const { data: varData, offset } = vars[varName];
    for (let currentOffset = data.length; currentOffset < offset; currentOffset++) {
      data.push(0);
    }
    data.push(...varData);
  }

  // padding
  if (data.length % 2 !== 0) {
    data.push(0);
  }

  return data;
};

const buildImage = (programName) => {
  // read and compile program
  const dirName = path.dirname(fileURLToPath(import.meta.url));
  const sourceCode = fs.readFileSync(path.resolve(`${dirName}/programs/${programName}.i432`), 'utf8');
  const { bytecode, stack, data, instructionsMap } = compile(sourceCode);
  const varsData = buildVarsSegmentContent(data.vars);

  const processorObjectTable = new ObjectTable('objectTableProcessor');
  // empty, would not be used
  const tempDirObjectTable = new ObjectTable('objectTableTemp');
  const mainObjectTable = new ObjectTable('objectTableMain');
  const directoryObjectTable = new ObjectTable('objectTableDirectory');

  const objectDirectory = new ObjectTableDirectory(directoryObjectTable);
  objectDirectory.addObjectTable(processorObjectTable);
  objectDirectory.addObjectTable(tempDirObjectTable);
  objectDirectory.addObjectTable(directoryObjectTable);
  objectDirectory.addObjectTable(mainObjectTable);

  // processors object table contains only processor access segments
  processorObjectTable.addObject(new ProcessorAccessSegment('processorAccess', { directoryObjectTable }));

  // interconnect segment for UART output
  mainObjectTable.addInterconnectSegment('uartInterconnect', 0x1000, 0x10);

  // here is all objects, except processor access segments
  mainObjectTable.addObject(new ProcessorDataSegment('processorData'));
  mainObjectTable.addObject(new LocalCommunicationSegment('processorLocalComms'));
  // delay port
  mainObjectTable.addObject(new PortDataSegment('delayPortData', { messageQueueSize: 1, portType: PORT_TYPE.DELAY }));
  mainObjectTable.addObject(new PortAccessSegment('delayPortAccess', { directoryObjectTable, messageQueueSize: 1 }));
  mainObjectTable.addObject(new CarrierDataSegment('delayCarrierData', { carrierType: CARRIER_TYPE.PROCESSOR }));
  mainObjectTable.addObject(new CarrierAccessSegment('delayCarrierAccess', { directoryObjectTable }));
  // actual process objects
  mainObjectTable.addObject(new CarrierDataSegment('normalCarrierData', { carrierType: CARRIER_TYPE.PROCESSOR, hasMessage: true }));
  mainObjectTable.addObject(new CarrierAccessSegment('normalCarrierAccess', { directoryObjectTable, messageRef: 'processCarrierAccess' }));
  mainObjectTable.addObject(new CarrierDataSegment('processCarrierData', { carrierType: CARRIER_TYPE.PROCESSOR, hasMessage: true }));
  mainObjectTable.addObject(new CarrierAccessSegment('processCarrierAccess', { directoryObjectTable, carriedObjectRef: 'processAccess' }));
  mainObjectTable.addObject(new ProcessDataSegment('processData'));
  mainObjectTable.addObject(new ProcessAccessSegment('processAccess', { directoryObjectTable }));
  mainObjectTable.addObject(new ContextAccessSegment('processContext0Access', { directoryObjectTable, objectsRefs: ['uartInterconnect', 'processContext0Vars'] }));
  mainObjectTable.addObject(new ContextDataSegment('processContext0Data', { sp: 0 })); // stack grows upward, push increments SP, pop - decrements
  mainObjectTable.addObject(new GenericDataSegment('processContext0Stack', { size: stack.size, data: stack.data, type: SEGMENT_TYPE.OPERAND_STACK_DATA }));
  mainObjectTable.addObject(new GenericDataSegment('processContext0Vars', { data: varsData, type: SEGMENT_TYPE.GENERIC_DATA }));
  mainObjectTable.addObject(new DomainSegment('processContext0Domain', { directoryObjectTable, instructionsRefs: ['processContext0Instruction0'] }));
  mainObjectTable.addObject(new InstructionSegment('processContext0Instruction0', { directoryObjectTable, instructions: bytecode, contextIdx: 0 }));

  const objects = [];
  return {
    image: objectDirectory.serialize(objects),
    objects,
    instructionsMap,
    vars: Object.entries(data.vars).map(([name, { offset, size }]) => ({ name, offset, size })),
  };
};

export {
  buildImage,
};