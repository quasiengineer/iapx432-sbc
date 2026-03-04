// notation is LSB -> MSB

export const INSTRUCTION_CLASSES = {
  // order-0
  NONE: '011100',
  // order-1
  D8: '011110',
  D16: '011111',
  // order-2
  D8_D8: '100011',
  D8_BR: '0000',
  D16_D8: '100101',
  D16_D16: '0001',
  // order-3
  D16_D16_D16: '0100',
};

export const INSTRUCTION_OPCODES = {
  MOVE_TO_INTERCONNECT: '11110',
  ZERO_CHARACTER: '0',
  ONE_CHARACTER: '10',
  MOVE_CHARACTER: '00',
  MOVE_SHORT_ORD: '0000',
  SAVE_SHORT_ORD: '010',
  DECREMENT_SHORT_ORD: '0100',
  EQUAL_ZERO_SHORT_ORD: '00',
  BRANCH_FALSE: '1',
};

// naming declares operand format from first to last
export const INSTRUCTION_FORMATS = {
  // in datasheet stack references means:
  //   only stk present: stk = stack[SP]
  //   stk1/stk2 present, but no stk: stk1 = stack[SP], stk2 = stack[SP - 1]
  //   stk1/stk2/stk present: stk1 = stack[SP], stk2 = stack[SP - 1], stk = stack[SP - 2]
  // my notation is more straightforward: stk1 = stack[SP], stk2 = stack[SP - 1], stk3 = stack[SP - 2]
  STK1_STK2_STK3: '1101',
  STK2_STK1_STK3: '1011',

  REF1_REF2_REF3: '0000',

  // 2-order instructions
  REF1_STK1: '10',
  REF1_REF1: '01',
  STK1_STK1: '111',
  STK1_REF1: '110',

  // 1-order instructions
  STK1: '1',
  REF1: '0',
};

export const INSTRUCTION_DATA_REF_SEGMENT_CTRL = {
  DIRECT_SHORT: '00',
  DIRECT_LONG: '01',
};

export const INSTRUCTION_DATA_REF_DISPL_CTRL = {
  SCALAR: '00',
  STATIC_VECTOR: '01',
};

export const INSTRUCTION_DATA_REF_DISPL_LEN = {
  BIT7: '0',
  BIT16: '1',
};

export const INSTRUCTION_DATA_REF_DISPL_BASE_LEN = {
  BIT0: '0',
  BIT16: '1',
};

export const INSTRUCTION_DATA_REF_DISPL_INDIRECT_TYPE = {
  STACK: '1',
  INTRASEGMENT: '01',
};

export const INSTRUCTION_DATA_REF_BRANCH_TYPE = {
  RELATIVE: '0',
  ABSOLUTE: '1',
};
