import { ACCESS_DESCRIPTOR_SIZE, createAccessDescriptor } from "../storage/accessDescriptors.js";
import { write32bit } from "../storage/base.js";
import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";

export class PortAccessSegment extends BaseObject {
  #messageQueueSize;

  constructor(ref, params) {
    super(ref, params);
    this.#messageQueueSize = params.messageQueueSize ?? 1;
  }

  get isAccess() {
    return true;
  }

  get type() {
    return SEGMENT_TYPE.PORT_ACCESS;
  }

  get size() {
    return (4 + this.#messageQueueSize) * ACCESS_DESCRIPTOR_SIZE;
  }

  serialize(image, baseAddress) {
    const objTableIdx = this.directoryObjectTable.getObjectIndex('objectTableMain');
    const objTable = this.directoryObjectTable.objects[objTableIdx - 1];

    // data segment
    write32bit(image, baseAddress + 0x00, createAccessDescriptor(objTableIdx, objTable.getObjectIndex('delayPortData')));
    // head of carrier queue
    write32bit(image, baseAddress + 0x04, 0);
    // tail of carrier queue
    write32bit(image, baseAddress + 0x08, 0);

    return this.size;
  }
}