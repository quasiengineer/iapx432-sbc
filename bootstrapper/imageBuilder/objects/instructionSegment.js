import { write16bit, write32bit } from "../storage/base.js";
import { SEGMENT_TYPE } from "../storage/objectTableDesciptors.js";
import { BaseObject } from "./baseObject.js";

export const INSTRUCTION_HEADER_SIZE = 7 * 2;

export class InstructionSegment extends BaseObject {
  #instructions;
  #contextIdx;

  constructor(ref, params) {
    super(ref, params);
    this.#instructions = params.instructions;
    this.#contextIdx = params.contextIdx;
  }

  get isAccess() {
    return false;
  }

  get type() {
    return SEGMENT_TYPE.INSTRUCTION_DATA;
  }

  get size() {
    return this.#instructions.length + INSTRUCTION_HEADER_SIZE;
  }

  serialize(image, baseAddress) {
    const objTableIdx = this.directoryObjectTable.getObjectIndex('objectTableMain');
    const objTable = this.directoryObjectTable.objects[objTableIdx - 1];

    // context access segment length
    write16bit(image, baseAddress, objTable.objects[objTable.getObjectIndex(`processContext${this.#contextIdx}Access`) - 1].size - 1);
    // context data segment length
    write16bit(image, baseAddress + 2, objTable.objects[objTable.getObjectIndex(`processContext${this.#contextIdx}Data`) - 1].size - 1);
    // operand stack segment length  + initial instruction offset (in bits)
    write32bit(image, baseAddress + 4, 0x0 | ((INSTRUCTION_HEADER_SIZE * 8) << 16));
    // constants segment index + fault object index
    write32bit(image, baseAddress + 8, 0x0);
    // trace object index
    write16bit(image, baseAddress + 12, 0);
    // instructions bit-stream
    for (let addr = baseAddress + 14, idx = 0; idx < this.#instructions.length; ++idx, ++addr) {
      image[addr] = this.#instructions[idx];
    }

    return this.size;
  }
}