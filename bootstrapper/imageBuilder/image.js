import { ObjectTableDirectory } from './storage/objectTableDirectory.js';
import { ObjectTable } from './storage/objectTable.js';
import { ProcessorAccessSegment } from './objects/processorAccessSegment.js';
import { ProcessorDataSegment } from './objects/processorDataSegment.js';
import { LocalCommunicationSegment } from './objects/localCommunicationSegment.js';

const buildImage = () => {
  console.log('Building image...');

  const processorObjectTable = new ObjectTable('objectTableProcessor');
  // empty, would not be used
  const tempObjectDirTable = new ObjectTable('objectTableTemp');
  const mainObjectTable = new ObjectTable('objectTableMain');
  const directoryObjectTable = new ObjectTable('objectTableDirectory');

  const objectDirectory = new ObjectTableDirectory(directoryObjectTable);
  objectDirectory.addObjectTable(processorObjectTable); // descriptor lays at 0x18
  objectDirectory.addObjectTable(tempObjectDirTable);   // descriptor lays at 0x28
  objectDirectory.addObjectTable(directoryObjectTable); // descriptor lays at 0x38
  objectDirectory.addObjectTable(mainObjectTable);      // descriptor lays at 0x48

  // processors object table contains only processor access segments
  processorObjectTable.addObject(new ProcessorAccessSegment('processor0access', directoryObjectTable));

  // here is all objects, except processor access segments
  mainObjectTable.addObject(new ProcessorDataSegment('processor0data'));
  mainObjectTable.addObject(new LocalCommunicationSegment('processor0localComms'));

  const segments = [];
  return { image: objectDirectory.serialize(segments), segments };
};

export {
  buildImage,
};