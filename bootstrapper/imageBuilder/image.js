import { maxWrittenAddr } from './base.js';
import { SEGMENT_TYPE, writeStorageDescriptor } from './storageDesciptors.js';

const buildImage = () => {
  const image = new Uint8Array(65536);

  writeStorageDescriptor(
    image,
    0x18,
    { isAccess: false, address: 0x100, length: 256, type: SEGMENT_TYPE.OBJECT_TABLE_DATA },
  );

  return image.slice(0, maxWrittenAddr + 1);
};

export {
  buildImage,
};