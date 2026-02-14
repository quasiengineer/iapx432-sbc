import { BaseObject } from '../objects/baseObject.js';
import { writeObjectTableDescriptor, SEGMENT_DESCRIPTOR_SIZE, SEGMENT_TYPE, updateSegmentAddress } from './objectTableDesciptors.js';
import { toHex } from '../../format.js';

export class ObjectTable extends BaseObject {
  #objects = [];

  addObject(object) {
    this.#objects.push(object);
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

  #serializeToImage(image, baseAddress, segments) {
    // skip header
    let address = baseAddress + SEGMENT_DESCRIPTOR_SIZE;
    // put descriptors
    for (const object of this.#objects) {
      writeObjectTableDescriptor(image, address, {
        isAccess: object.isAccess,
        address,
        length: object.size,
        type: object.type,
      });

      address += SEGMENT_DESCRIPTOR_SIZE;
    }

    // put object tables and their objects
    for (const object of this.#objects) {
      // object table directory has reference to itself, so skip it
      if (object !== this) {
        object.address = address;
        segments.push({ ref: object.ref, address, size: object.size });
        address += object.serialize(image, address, segments);
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

  serialize(image, address, segments) {
    const size = this.#serializeToImage(image, address, segments);
    this.#fixReferences(image, address);
    return size;
  }
}