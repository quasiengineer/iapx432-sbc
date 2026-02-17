import { ACCESS_DESCRIPTOR_SIZE, createAccessDescriptor } from "../storage/accessDescriptors.js";
import { write32bit } from "../storage/base.js";
import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";

export class ProcessAccessSegment extends BaseObject {
  constructor(ref, params) {
    super(ref, params);
  }

  get isAccess() {
    return true;
  }

  get type() {
    return SEGMENT_TYPE.PROCESS_ACCESS;
  }

  get size() {
    return 12 * ACCESS_DESCRIPTOR_SIZE;
  }

  serialize(image, baseAddress) {
    const objTableIdx = this.directoryObjectTable.getObjectIndex('objectTableMain');
    const objTable = this.directoryObjectTable.objects[objTableIdx - 1];

    // data segment
    const dataSegmentRef = this.ref.replace(/Access$/, 'Data');
    write32bit(image, baseAddress + 0x00, createAccessDescriptor(objTableIdx, objTable.getObjectIndex(dataSegmentRef)));
    // current context
    write32bit(image, baseAddress + 0x04, 0);
    // globals access segment
    write32bit(image, baseAddress + 0x08, 0);
    // local object table
    write32bit(image, baseAddress + 0x0C, 0);
    // process carrier
    write32bit(image, baseAddress + 0x10, 0);
    // dispatching port
    write32bit(image, baseAddress + 0x14, 0);
    // scheduling port
    write32bit(image, baseAddress + 0x18, 0);
    // fault port
    write32bit(image, baseAddress + 0x1C, 0);
    // current message
    write32bit(image, baseAddress + 0x20, 0);
    // current port
    write32bit(image, baseAddress + 0x24, 0);
    // current carrier
    write32bit(image, baseAddress + 0x28, 0);
    // surrogate carrier
    write32bit(image, baseAddress + 0x2C, 0);

    return this.size;
  }
}