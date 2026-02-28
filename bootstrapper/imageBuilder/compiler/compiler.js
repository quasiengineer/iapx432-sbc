import { INSTRUCTION_CLASSES, INSTRUCTION_FORMATS, INSTRUCTION_OPCODES } from './instructions.js';

const bitStreamToByteArray = (bitStream) => {
  const byteArray = [];
  for (let i = 0; i < bitStream.length; i += 8) {
    byteArray.push(parseInt(bitStream.substr(i, 8).split('').reverse().join(''), 2));
  }

  return byteArray;
};

const compileInstruction = (iclass, format = '', references = [], opcode = '') => {
  return `${iclass}${format}${references.join('')}${opcode}`;
};

export const compile = (sourceCode) => {
  let bitStream = '';

  const instructions = sourceCode.split('\n').map((x) => x.trim()).filter(Boolean);
  for (const instruction of instructions) {
    const [opcode] = instruction.split(' ');
    switch (opcode) {
      case 'RETURN_FROM_CONTEXT':
        bitStream += compileInstruction(INSTRUCTION_CLASSES.NONE);
        break;

      case 'MOVE_TO_INTERCONNECT':
        bitStream += compileInstruction(
          INSTRUCTION_CLASSES.D16_D16_D16,
          INSTRUCTION_FORMATS.STK1_STK2_STK3,
          [],
          INSTRUCTION_OPCODES.MOVE_TO_INTERCONNECT,
        );
        break;
    }
  }

  // insttruction segment should have size multiple of 4
  const bytes = bitStreamToByteArray(bitStream);
  const padding = 4 - bytes.length % 4;
  for (let i = 0; i < padding; i++) {
    bytes.push(0);
  }

  return bytes;
};
