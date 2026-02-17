import { ACCESS_DESCRIPTOR_SIZE, createAccessDescriptor } from "../storage/accessDescriptors.js";
import { write32bit } from "../storage/base.js";
import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";

export const ACCESS_DESCRIPTORS_AMOUNT = 20;

export class ProcessorAccessSegment extends BaseObject {
  get isAccess() {
    return true;
  }

  get type() {
    return SEGMENT_TYPE.PROCESSOR_ACCESS;
  }

  get size() {
    return ACCESS_DESCRIPTORS_AMOUNT * ACCESS_DESCRIPTOR_SIZE;
  }

  serialize(image, baseAddress) {
    const mainObjectTableIdx = this.directoryObjectTable.getObjectIndex('objectTableMain');
    const directoryObjectTableIdx = this.directoryObjectTable.getObjectIndex('objectTableDirectory');

    const mainObjectTable = this.directoryObjectTable.objects[mainObjectTableIdx - 1];

    const normalCarrierAD = createAccessDescriptor(mainObjectTableIdx, mainObjectTable.getObjectIndex('normalCarrierAccess'));

    const accessDescriptors = [
      // +0x00 processor data segment
      createAccessDescriptor(mainObjectTableIdx, mainObjectTable.getObjectIndex('processorData')),
      // +0x04 current process carrier
      0x0,
      // +0x08 local communication segment
      createAccessDescriptor(mainObjectTableIdx, mainObjectTable.getObjectIndex('processorLocalComms')),
      // +0x0C global communication segment
      0x0,
      // +0x10 object table directory
      createAccessDescriptor(directoryObjectTableIdx, directoryObjectTableIdx),
      // +0x14 processor carrier object (AD sourced from other carriers)
      normalCarrierAD,
      // +0x18 delay port
      createAccessDescriptor(mainObjectTableIdx, mainObjectTable.getObjectIndex('delayPortAccess')),
      // +0x1C delay carrier
      createAccessDescriptor(mainObjectTableIdx, mainObjectTable.getObjectIndex('delayCarrierAccess')),
      // +0x20 current message
      0x0,
      // +0x24 current port
      0x0,
      // +0x28 current carrier
      0x0,
      // +0x2C surrogate carrier
      0x0,
      // +0x30 normal port
      0x0,
      // +0x34 alarm port
      0x0,
      // +0x38 reconfiguration port
      0x0,
      // +0x3C diagnostic port
      0x0,
      // +0x40 carrier to normal port
      normalCarrierAD,
      // +0x44 carrier to alarm port
      0x0,
      // +0x48 carrier to reconfiguration port
      0x0,
      // +0x4C carrier to diagnostic port
      0x0,
    ];

    let address = baseAddress;
    for (let i = 0; i < ACCESS_DESCRIPTORS_AMOUNT; i++, address += ACCESS_DESCRIPTOR_SIZE) {
      write32bit(image, address, accessDescriptors[i]);
    }

    return address - baseAddress;
  }
}