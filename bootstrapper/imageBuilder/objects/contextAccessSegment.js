import { ACCESS_DESCRIPTOR_SIZE, createAccessDescriptor } from "../storage/accessDescriptors.js";
import { write32bit } from "../storage/base.js";
import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";

export class ContextAccessSegment extends BaseObject {
  #objectsRefs;

  constructor(ref, params) {
    super(ref, params);

    this.#objectsRefs = params.objectsRefs || [];
  }

  get isAccess() {
    return true;
  }

  get type() {
    return SEGMENT_TYPE.CONTEXT_ACCESS;
  }

  get size() {
    return (10 + this.#objectsRefs.length) * ACCESS_DESCRIPTOR_SIZE;
  }

  serialize(image, baseAddress) {
    const objTableIdx = this.directoryObjectTable.getObjectIndex('objectTableMain');
    const objTable = this.directoryObjectTable.objects[objTableIdx - 1];

    const [, idx] = this.ref.match(/^processContext(\d+)Access$/);

    // data segment
    write32bit(image, baseAddress + 0x00, createAccessDescriptor(objTableIdx, objTable.getObjectIndex(`processContext${idx}Data`)));
    // constants data segment
    write32bit(image, baseAddress + 0x04, 0);
    // previous context
    write32bit(image, baseAddress + 0x08, 0);
    // message object
    write32bit(image, baseAddress + 0x0C, 0);
    // current context
    write32bit(image, baseAddress + 0x10, createAccessDescriptor(objTableIdx, objTable.getObjectIndex(this.ref)));
    // entry access segment 1
    write32bit(image, baseAddress + 0x14, 0);
    // entry access segment 2
    write32bit(image, baseAddress + 0x18, 0);
    // entry access segment 3
    write32bit(image, baseAddress + 0x1C, 0);
    // domain of definition
    write32bit(image, baseAddress + 0x20, createAccessDescriptor(objTableIdx, objTable.getObjectIndex(`processContext${idx}Domain`)));
    // context's operand stack
    write32bit(image, baseAddress + 0x24, createAccessDescriptor(objTableIdx, objTable.getObjectIndex(`processContext${idx}Stack`)));
    // write32bit(image, baseAddress + 0x24, 0);

    // access descriptors for objects
    for (let i = 0; i < this.#objectsRefs.length; i++) {
      write32bit(image, baseAddress + 0x28 + i * ACCESS_DESCRIPTOR_SIZE, createAccessDescriptor(objTableIdx, objTable.getObjectIndex(this.#objectsRefs[i])));
    }

    return this.size;
  }
}