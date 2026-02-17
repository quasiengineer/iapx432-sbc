import { ObjectTableDirectory } from './storage/objectTableDirectory.js';
import { ObjectTable } from './storage/objectTable.js';
import { ProcessorAccessSegment } from './objects/processorAccessSegment.js';
import { ProcessorDataSegment } from './objects/processorDataSegment.js';
import { LocalCommunicationSegment } from './objects/localCommunicationSegment.js';
import { PortDataSegment, PORT_TYPE } from './objects/portDataSegment.js';
import { PortAccessSegment } from './objects/portAccessSegment.js';
import { CARRIER_TYPE, CarrierDataSegment } from './objects/carrierDataSegment.js';
import { CarrierAccessSegment } from './objects/carrierAccessSegment.js';

const buildImage = () => {
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
  processorObjectTable.addObject(new ProcessorAccessSegment('processor0access', { directoryObjectTable }));

  // here is all objects, except processor access segments
  mainObjectTable.addObject(new ProcessorDataSegment('processor0data'));
  mainObjectTable.addObject(new LocalCommunicationSegment('processor0localComms'));
  mainObjectTable.addObject(new PortDataSegment('delayPortData', { messageQueueSize: 1, portType: PORT_TYPE.DELAY }));
  mainObjectTable.addObject(new PortAccessSegment('delayPortAccess', { directoryObjectTable, messageQueueSize: 1 }));
  mainObjectTable.addObject(new CarrierDataSegment('delayCarrierData', { carrierType: CARRIER_TYPE.PROCESSOR }));
  mainObjectTable.addObject(new CarrierAccessSegment('delayCarrierAccess', { directoryObjectTable }));

  const segments = [];
  return { image: objectDirectory.serialize(segments), segments };
};

export {
  buildImage,
};