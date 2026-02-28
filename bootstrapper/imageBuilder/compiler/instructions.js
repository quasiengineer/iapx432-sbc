// notation is LSB -> MSB

export const INSTRUCTION_CLASSES = {
  NONE: '011100',
  D16_D16_D16: '0100',
};

export const INSTRUCTION_OPCODES = {
  MOVE_TO_INTERCONNECT: '11110',
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
};