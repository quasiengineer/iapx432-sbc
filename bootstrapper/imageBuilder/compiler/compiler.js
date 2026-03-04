import {
  INSTRUCTION_CLASSES,
  INSTRUCTION_FORMATS,
  INSTRUCTION_OPCODES,
  INSTRUCTION_DATA_REF_DISPL_CTRL,
  INSTRUCTION_DATA_REF_DISPL_LEN,
  INSTRUCTION_DATA_REF_DISPL_BASE_LEN,
  INSTRUCTION_DATA_REF_DISPL_INDIRECT_TYPE,
  INSTRUCTION_DATA_REF_SEGMENT_CTRL,
  INSTRUCTION_DATA_REF_BRANCH_TYPE,
} from './instructions.js';

import { INSTRUCTION_HEADER_SIZE } from '../objects/instructionSegment.js';

const INSTRUCTION_ENCODINGS = {
  'RETURN_FROM_CONTEXT': [INSTRUCTION_CLASSES.NONE],
  'MOVE_TO_INTERCONNECT': [INSTRUCTION_CLASSES.D16_D16_D16, INSTRUCTION_OPCODES.MOVE_TO_INTERCONNECT],
  'ZERO_CHARACTER': [INSTRUCTION_CLASSES.D8, INSTRUCTION_OPCODES.ZERO_CHARACTER],
  'ONE_CHARACTER': [INSTRUCTION_CLASSES.D8, INSTRUCTION_OPCODES.ONE_CHARACTER],
  'MOVE_CHARACTER': [INSTRUCTION_CLASSES.D8_D8, INSTRUCTION_OPCODES.MOVE_CHARACTER],
  'MOVE_SHORT_ORD': [INSTRUCTION_CLASSES.D16_D16, INSTRUCTION_OPCODES.MOVE_SHORT_ORD],
  'SAVE_SHORT_ORD': [INSTRUCTION_CLASSES.D16, INSTRUCTION_OPCODES.SAVE_SHORT_ORD],
  'DECREMENT_SHORT_ORD': [INSTRUCTION_CLASSES.D16_D16, INSTRUCTION_OPCODES.DECREMENT_SHORT_ORD],
  'EQUAL_ZERO_SHORT_ORD': [INSTRUCTION_CLASSES.D16_D8, INSTRUCTION_OPCODES.EQUAL_ZERO_SHORT_ORD],
  'BRANCH_FALSE': [INSTRUCTION_CLASSES.D8_BR, INSTRUCTION_OPCODES.BRANCH_FALSE],
};

const bitStreamToByteArray = (bitStream) => {
  const byteArray = [];
  for (let i = 0; i < bitStream.length; i += 8) {
    byteArray.push(parseInt(bitStream.substr(i, 8).split('').reverse().join(''), 2));
  }

  return byteArray;
};

// EAS = 00, slot = 1 (constants data segment)
const DATA_SEGMENT_OBJ_SELECTOR = '001000';

const encodeOperand = (operand, varsInfo) => {
  if (operand.match(/^[01_]+$/)) {
    return operand.replaceAll(/_/g, '');
  }

  const [, arrayName, index] = operand.match(/^([\w\$]+)\[([\w\$]+)\]$/) || [];
  if (arrayName && index) {
    if (arrayName !== '$data') {
      throw new Error(`Array variables (${arrayName}) are not supported`);
    }

    if (!varsInfo.vars[index]) {
      throw new Error(`Variable ${index} not found`);
    }

    return INSTRUCTION_DATA_REF_DISPL_CTRL.STATIC_VECTOR
      + INSTRUCTION_DATA_REF_SEGMENT_CTRL.DIRECT_SHORT
      + INSTRUCTION_DATA_REF_DISPL_BASE_LEN.BIT0
      + DATA_SEGMENT_OBJ_SELECTOR
      + INSTRUCTION_DATA_REF_DISPL_INDIRECT_TYPE.INTRASEGMENT
      + INSTRUCTION_DATA_REF_DISPL_LEN.BIT7
      + varsInfo.vars[index].offset.toString(2).padStart(7, '0').split('').reverse().join('')
  }

  if (!varsInfo.vars[operand]) {
    throw new Error(`Variable ${operand} not found`);
  }

  return INSTRUCTION_DATA_REF_DISPL_CTRL.SCALAR
    + INSTRUCTION_DATA_REF_SEGMENT_CTRL.DIRECT_SHORT
    + INSTRUCTION_DATA_REF_DISPL_LEN.BIT7
    + DATA_SEGMENT_OBJ_SELECTOR
    + varsInfo.vars[operand].offset.toString(2).padStart(7, '0').split('').reverse().join('')
};

const encodeOperands = (operands, varsInfo) => {
  switch (operands.length) {
    case 3:
      if (operands[0] === '$st0' || operands[1] === '$st1' || operands[2] === '$st2') {
        return INSTRUCTION_FORMATS.STK1_STK2_STK3;
      }

      // XXX: only ref1/ref2/ref3 for now
      return `${INSTRUCTION_FORMATS.REF1_REF2_REF3}${encodeOperand(operands[0], varsInfo)}${encodeOperand(operands[1], varsInfo)}${encodeOperand(operands[2], varsInfo)}`;

    case 1:
      if (operands[0] === '$st0') {
        return INSTRUCTION_FORMATS.STK1;
      }

      return `${INSTRUCTION_FORMATS.REF1}${encodeOperand(operands[0], varsInfo)}`;

    case 2:
      if (operands[0] === '$st0' && operands[1] === '$st0') {
        return INSTRUCTION_FORMATS.STK1_STK1;
      }

      if (operands[1] === '$st0') {
        return `${INSTRUCTION_FORMATS.REF1_STK1}${encodeOperand(operands[0], varsInfo)}`;
      }

      if (operands[0] === '$st0') {
        return `${INSTRUCTION_FORMATS.STK1_REF1}${encodeOperand(operands[1], varsInfo)}`;
      }

      if (operands[0] === operands[1]) {
        return `${INSTRUCTION_FORMATS.REF1_REF1}${encodeOperand(operands[0], varsInfo)}`;
      }

      throw new Error('Unsupported operand type');

    case 0:
      return '';

    default:
      throw new Error('Invalid operand count');
  }
};

const compileInstruction = (iclass, operands = '', opcode = '') => {
  return `${iclass}${operands}${opcode}`;
};

const compileBranchInstruction = (baseOffset, iclass, opcode, operands, varsInfo, refs) => {
  const refPlaceholder = '0000000000000000';

  // stack as operand
  if (operands[0] === '$st0') {
    const instrOffset = iclass.length + INSTRUCTION_FORMATS.STK1.length + INSTRUCTION_DATA_REF_BRANCH_TYPE.ABSOLUTE.length;
    refs.push({ label: operands[1], offset: baseOffset + instrOffset });
    return `${iclass}${INSTRUCTION_FORMATS.STK1}${INSTRUCTION_DATA_REF_BRANCH_TYPE.ABSOLUTE}${refPlaceholder}${opcode}`;
  }

  // variable as operand
  const encodedOperand = encodeOperand(operands[0], varsInfo);
  const instrOffset = iclass.length + INSTRUCTION_FORMATS.REF1.length + encodedOperand.length + INSTRUCTION_DATA_REF_BRANCH_TYPE.ABSOLUTE.length;
  refs.push({ label: operands[1], offset: baseOffset + instrOffset });
  return `${iclass}${INSTRUCTION_FORMATS.REF1}${encodedOperand}${INSTRUCTION_DATA_REF_BRANCH_TYPE.ABSOLUTE}${refPlaceholder}${opcode}`;
};

export const compile = (sourceCode) => {
  const lines = sourceCode.split('\n').map((x) => x.trim()).filter((line) => line.length && line[0] !== '#');

  const stackInfo = {};
  const dataInfo = {};
  let instructionStart = 0;

  // Parse directives first
  for (let i = 0; i < lines.length; i++) {
    if (lines[i][0] !== '.') {
      instructionStart = i;
      break;
    }

    const directiveName = (lines[i].match(/^\.(\w+)\s*\{$/) || [])[1];
    if (!directiveName) {
      throw new Error('Invalid directive');
    }

    let content = '';
    i++; // Move to next line
    while (i < lines.length && lines[i] !== '}') {
      content += lines[i] + '\n';
      i++;
    }
    if (i >= lines.length) {
      throw new Error('Unclosed directive');
    }

    switch (directiveName) {
      case 'stack': {
        const sizeMatch = content.match(/size\s*=\s*(0x[0-9a-fA-F]+)/);
        const dataMatch = content.match(/data\s*=\s*\[([\s\S]*?)\]/);
        if (!sizeMatch || !dataMatch) {
          throw new Error('Invalid stack directive');
        }

        stackInfo.size = parseInt(sizeMatch[1], 16);
        const dataStr = dataMatch[1];
        stackInfo.data = dataStr.split(',').map(x => parseInt(x.trim(), 16)).filter(x => !isNaN(x));
        break;
      }

      case 'data': {
        const contentLines = content.split('\n').map(x => x.trim()).filter(x => x);
        dataInfo.vars = {};

        let offset = 0;
        for (const line of contentLines) {
          const varMatch = line.match(/(\w+)\s*=\s*\{\s*size\s*=\s*(\d+),\s*data\s*=\s*\[([^\]]*)\]\s*\}/);
          if (!varMatch) {
            throw new Error(`Invalid var definition: ${line}`);
          }

          const name = varMatch[1];
          const size = parseInt(varMatch[2]);
          const dataStr = varMatch[3];
          const data = dataStr ? dataStr.split(',').map(x => parseInt(x.trim(), 16)).filter(x => !isNaN(x)) : [];
          dataInfo.vars[name] = { size, data, offset };
          offset += size;
        }

        break;
      }

      default:
        throw new Error(`Unknown directive: ${directiveName}`);
    }
  }

  // Parse instructions
  const instructionsMap = new Map();
  const refs = [];
  const labels = {};
  let bitStream = '';
  let offset = INSTRUCTION_HEADER_SIZE * 8;
  for (let i = instructionStart; i < lines.length; i++) {
    if (lines[i].endsWith(':')) {
      labels[lines[i].slice(0, -1)] = offset;
      continue;
    }

    const [instruction, ...operands] = lines[i].split(' ');
    const [iclass, opcode = ''] = INSTRUCTION_ENCODINGS[instruction];
    const isBranch = iclass === INSTRUCTION_CLASSES.D8_BR;
    const encodedInstruction = isBranch
      ? compileBranchInstruction(offset, iclass, opcode, operands, dataInfo, refs)
      : compileInstruction(iclass, encodeOperands(operands, dataInfo), opcode);
    bitStream += encodedInstruction;
    instructionsMap.set(offset, lines[i]);
    offset += encodedInstruction.length;
  }

  // fix references to labels
  for (const { label, offset } of refs) {
    const labelAddress = labels[label];
    if (labelAddress === undefined) {
      throw new Error(`Label not found: ${label}`);
    }

    const relOffset = offset - INSTRUCTION_HEADER_SIZE * 8;
    const branchRef = labelAddress.toString(2).padStart(16, '0').split('').reverse().join('');
    bitStream = bitStream.slice(0, relOffset) + branchRef + bitStream.slice(relOffset + 16);
  }

  // instruction segment should have proper padding
  const bytes = bitStreamToByteArray(bitStream);
  const padding = 4 - bytes.length % 4;
  for (let i = 0; i < padding + 4; i++) {
    bytes.push(0);
  }

  return { bytecode: bytes, stack: stackInfo, data: dataInfo, instructionsMap };
};
