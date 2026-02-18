import { ACCESS_DESCRIPTOR_SIZE, createAccessDescriptor } from "../storage/accessDescriptors.js";
import { write32bit } from "../storage/base.js";
import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";

export class DomainSegment extends BaseObject {
  #instructionsRefs;

  constructor(ref, params) {
    super(ref, params);

    this.#instructionsRefs = params.instructionsRefs;
  }

  get isAccess() {
    return true;
  }

  get type() {
    return SEGMENT_TYPE.DOMAIN_ACCESS;
  }

  get size() {
    return this.#instructionsRefs.length * ACCESS_DESCRIPTOR_SIZE;
  }

  serialize(image, baseAddress) {
    const objTableIdx = this.directoryObjectTable.getObjectIndex('objectTableMain');
    const objTable = this.directoryObjectTable.objects[objTableIdx - 1];

    let addr = baseAddress;
    for (const ref of this.#instructionsRefs) {
      write32bit(image, addr, createAccessDescriptor(objTableIdx, objTable.getObjectIndex(ref)));
      addr += ACCESS_DESCRIPTOR_SIZE;
    }

    return this.size;
  }
}