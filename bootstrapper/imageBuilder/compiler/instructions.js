// notation is LSB -> MSB, datasheet format is reversed (LSB is on the right)

export const INSTRUCTION_CLASSES = {
  // order-0
  NONE: '011100',
  BR: '011101',
  // order-1
  D8: '011110',
  D16: '011111',
  D32: '100000',
  // order-2
  D8_D8: '100011',
  D8_BR: '0000',
  D8_D16: '100100',
  D16_D8: '100101',
  D16_D16: '0001',
  D16_D32: '100110',
  D32_D16: '101001',
  D32_D32: '0010',
  // order-3
  D8_D8_D8: '110010',
  D16_D16_D8: '0011',
  D16_D16_D16: '0100',
  D32_D32_D32: '0110',
};

export const INSTRUCTION_OPCODES = {
  MOVE_TO_INTERCONNECT: '11110',
  ZERO_1U: '0',
  SAVE_1U: '11',
  ONE_1U: '10',
  MOVE_1U: '00',
  DEC_1U: '101',
  INC_1U: '100',
  AND_1U: '000',
  ADD_1U: '100',
  SUB_1U: '101',
  GREATER_THAN_1U: '1110',
  EQUAL_ZERO_1U: '110',
  EQUAL_1U: '1100',
  CONVERT_1U_2U: '',
  MOVE_2U: '0000',
  SAVE_2U: '010',
  DEC_2U: '0100',
  INC_2U: '0011',
  ADD_2U: '0110',
  SUB_2U: '01110',
  MUL_2U: '01111',
  DIV_2U: '10000',
  ZERO_2U: '000',
  EQUAL_ZERO_2U: '00',
  EQUAL_2U: '000',
  GREATER_THAN_2U: '010',
  CONVERT_2U_4U: '00',
  ZERO_4U: '000',
  SAVE_4U: '010',
  MOVE_4U: '000',
  ADD_4U: '0101',
  MUL_4U: '0111',
  DIV_4U: '1000',
  REMINDER_4U: '1001',
  CONVERT_4U_2U: '01',
  BRANCH_TRUE: '0',
  BRANCH_FALSE: '1',
};

// naming declares operand format from first to last
export const INSTRUCTION_FORMATS = {
  // in datasheet stack references means:
  //   only stk present: stk = stack[SP]
  //   stk1/stk2 present, but no stk: stk1 = stack[SP], stk2 = stack[SP - 1]
  //   stk1/stk2/stk present: stk1 = stack[SP], stk2 = stack[SP - 1], stk = stack[SP - 2]
  // my notation is more straightforward: stk1 = stack[SP], stk2 = stack[SP - 1], stk3 = stack[SP - 2]


  // 3-order instructions
  // SOURCE[2] SOURCE[1] DESTINATION
  STK1_STK2_STK3: '1101',
  STK2_STK1_STK3: '1011',
  REF1_REF2_REF3: '0000',
  REF1_REF2_STK1: '0011',
  STK1_REF1_STK1: '1001',
  REF1_STK1_REF1: '0101',
  STK1_REF1_REF1: '1000',
  REF1_STK1_STK1: '0110',
  STK1_STK2_REF1: '1110',
  STK2_STK1_REF1: '1010',
  STK1_REF1_REF2: '0111',
  REF1_STK1_REF2: '0100',
  REF1_REF2_REF2: '0001',
  REF1_REF2_REF1: '0010',

  // 2-order instructions
  // SOURCE DESTINATION
  REF1_STK1: '10',
  REF1_REF1: '01',
  STK1_STK1: '111',
  STK1_REF1: '110',
  REF1_REF2: '00',

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
