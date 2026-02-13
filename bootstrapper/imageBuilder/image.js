import { ObjectTableDirectory } from './storage/objectTableDirectory.js';
import { ObjectTable } from './storage/objectTable.js';
import { ProcessorAccessSegment } from './objects/processorAccessSegment.js';
import { ProcessorDataSegment } from './objects/processorDataSegment.js';

const buildImage = () => {
  console.log('Building image...');

  const processorObjectTable = new ObjectTable('objectTableProcessor');
  // empty, would not be used
  const tempObjectDirTable = new ObjectTable('objectTableTemp');
  const mainObjectTable = new ObjectTable('objectTableMain');
  const directoryObjectTable = new ObjectTable('objectTableDirectory');

  const objectDirectory = new ObjectTableDirectory(directoryObjectTable);
  objectDirectory.addObjectTable(processorObjectTable);
  objectDirectory.addObjectTable(tempObjectDirTable);
  objectDirectory.addObjectTable(directoryObjectTable);
  objectDirectory.addObjectTable(mainObjectTable);

  // processors object table contains only processor access segments
  processorObjectTable.addObject(new ProcessorAccessSegment('processor0access', directoryObjectTable));

  // here is all objects, except processor access segments
  mainObjectTable.addObject(new ProcessorDataSegment('processor0data'));

  return objectDirectory.serialize();
};

export {
  buildImage,
};