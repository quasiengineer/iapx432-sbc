import { write32bit } from './base.js';

const SEGMENT_TYPE = {
  // access segments
  GENERIC_ACCESS:       0b00000,
  DOMAIN_ACCESS:        0b00010,
  CONTEXT_ACCESS:       0b00100,
  PROCESS_ACCESS:       0b00101,
  PROCESSOR_ACCESS:     0b00110,
  PORT_ACCESS:          0b00111,
  CARRIER_ACCESS:       0b01000,
  STORAGE_RSRC_ACCESS:  0b01001,
  TYPE_DEF_ACCESS:      0b01010,

  // data segments
  GENERIC_DATA:         0b00000,
  OPERAND_STACK_DATA:   0b00001,
  OBJECT_TABLE_DATA:    0b00010,
  INSTRUCTION_DATA:     0b00011,
  CONTEXT_DATA:         0b00100,
  PROCESS_DATA:         0b00101,
  PROCESSOR_DATA:       0b00110,
  PORT_DATA:            0b00111,
  CARRIER_DATA:         0b01000,
  STORAGE_RSRC_DATA:    0b01001,
  COMMUNICATION_DATA:   0b01010,
  DESCRIPTOR_CTRL_DATA: 0b01011,
  REFINEMENT_CTRL_DATA: 0b01100,
};

const PROCESSOR_CLASS = {
  All: 0b000,
  GDP: 0b001,
};

const GDP_SEGMENT_TYPES_ACCESS = [SEGMENT_TYPE.PROCESSOR_ACCESS, SEGMENT_TYPE.PROCESS_ACCESS, SEGMENT_TYPE.CONTEXT_ACCESS];
const GDP_SEGMENT_TYPES_DATA = [SEGMENT_TYPE.PROCESSOR_DATA, SEGMENT_TYPE.PROCESS_DATA, SEGMENT_TYPE.CONTEXT_DATA, SEGMENT_TYPE.OPERAND_STACK_DATA, SEGMENT_TYPE.INSTRUCTION_DATA];

const writeStorageDescriptor = (image, desciptorAddr, descriptor) => {
  const { isAccess, address, length, type } = descriptor;

  const GDPSegmentTypes = isAccess ? GDP_SEGMENT_TYPES_ACCESS : GDP_SEGMENT_TYPES_DATA;
  const processorClass = GDPSegmentTypes.includes(type) ? PROCESSOR_CLASS.GDP : PROCESSOR_CLASS.All;

  const word0 =
    0b11 // descriptor type
    | (1 << 2) // valid, should be 1
    | (isAccess ? (1 << 3) : 0) // base type, 0 = data segment, 1 = access segment
    | (1 << 4) // storage associated, should be 1
    | (0 << 5) // i/o lock, if it's locked by IP
    | (0 << 6) // altered, dirty flag for segment
    | (0 << 7) // accessed, toched flag for segment
    | (address << 8);

  const word1 = length - 1;

  const word2 =
    type
    | (processorClass << 5) // processor class
    | (0 << 8)              // reclamation, 0 if there is no access descriptor references segment
    | (0 << 16)             // level number, 0 for globally allocated segments
  ;

  const word3 = 1; // dirty bit, 0 if segment has only zeroes

  write32bit(image, desciptorAddr, word0);
  write32bit(image, desciptorAddr + 4, word1);
  write32bit(image, desciptorAddr + 8, word2);
  write32bit(image, desciptorAddr + 12, word3);
};

export {
  writeStorageDescriptor,

  SEGMENT_TYPE,
};
