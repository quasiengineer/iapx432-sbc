import { BaseObject } from '../objects/baseObject.js';

import {
  writeStorageDescriptor,
  writeInterconnectDescriptor,
  updateSegmentAddress,
  SEGMENT_DESCRIPTOR_SIZE,
  SEGMENT_TYPE,
} from './objectTableDesciptors.js';

export class ObjectTable extends BaseObject {
  #objects = [];

  addObject(object) {
    this.#objects.push(object);
  }

  addInterconnectSegment(ref, address, length) {
    this.#objects.push({ ref, address, length, type: 'interconnect' });
  }

  getObjectIndex(ref) {
    // +1 because the first entry is the header
    const idx = this.#objects.findIndex((object) => object.ref === ref) + 1;
    if (idx === 0) {
      throw new Error(`Object with ref ${ref} not found in object table`);
    }

    return idx;
  }

  get objects() {
    return this.#objects;
  }

  get isAccess() {
    return false;
  }

  get type() {
    return SEGMENT_TYPE.OBJECT_TABLE_DATA;
  }

  get size() {
    // +1 for header
    return (this.#objects.length + 1) * SEGMENT_DESCRIPTOR_SIZE;
  }

  #serializeToImage(image, baseAddress, objects) {
    // skip header
    let address = baseAddress + SEGMENT_DESCRIPTOR_SIZE;
    // put storage descriptors
    for (const object of this.#objects) {
      if (object.type === 'interconnect') {
        writeInterconnectDescriptor(image, address, { address: object.address, length: object.length });
      } else {
        writeStorageDescriptor(image, address, {
          isAccess: object.isAccess,
          address,
          length: object.size,
          type: object.type,
        });
      }

      address += SEGMENT_DESCRIPTOR_SIZE;
    }

    // put object tables and their objects
    for (const object of this.#objects) {
      // object table directory has reference to itself, so skip it
      if (object !== this && !object.address) {
        object.address = address;
        objects.push(object);
        address += object.serialize(image, address, objects) || 0;
      }
    }

    return address - baseAddress;
  }

  #fixReferences(image, baseAddress) {
    let address = baseAddress + SEGMENT_DESCRIPTOR_SIZE;
    for (const object of this.#objects) {
      updateSegmentAddress(image, address, object.address);
      address += SEGMENT_DESCRIPTOR_SIZE;
    }
  }

  serialize(image, address, objects) {
    const size = this.#serializeToImage(image, address, objects);
    this.#fixReferences(image, address);
    return size;
  }
}