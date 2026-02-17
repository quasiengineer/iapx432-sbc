import { ACCESS_DESCRIPTOR_SIZE, createAccessDescriptor } from "../storage/accessDescriptors.js";
import { write32bit } from "../storage/base.js";
import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";

export class CarrierAccessSegment extends BaseObject {
  constructor(ref, params) {
    super(ref, params);
  }

  get isAccess() {
    return true;
  }

  get type() {
    return SEGMENT_TYPE.CARRIER_ACCESS;
  }

  get size() {
    return 9 * ACCESS_DESCRIPTOR_SIZE;
  }

  serialize(image, baseAddress) {
    const objTableIdx = this.directoryObjectTable.getObjectIndex('objectTableMain');
    const objTable = this.directoryObjectTable.objects[objTableIdx - 1];

    // data segment
    const dataSegmentRef = this.ref.replace(/Access$/, 'Data');
    write32bit(image, baseAddress + 0x00, createAccessDescriptor(objTableIdx, objTable.getObjectIndex(dataSegmentRef)));
    // next carrier in queue
    write32bit(image, baseAddress + 0x04, 0);
    // current port
    write32bit(image, baseAddress + 0x08, 0);
    // second port
    write32bit(image, baseAddress + 0x0C, 0);
    // maintenance port
    write32bit(image, baseAddress + 0x10, 0);
    // refined carrier
    write32bit(image, baseAddress + 0x14, 0);
    // outgoing message
    write32bit(image, baseAddress + 0x18, 0);
    // incoming message
    write32bit(image, baseAddress + 0x1C, 0);
    // carried object
    write32bit(image, baseAddress + 0x20, 0);

    return this.size;
  }
}