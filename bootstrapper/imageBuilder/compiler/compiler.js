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
  'ZERO_1U': [INSTRUCTION_CLASSES.D8, INSTRUCTION_OPCODES.ZERO_1U],
  'ONE_1U': [INSTRUCTION_CLASSES.D8, INSTRUCTION_OPCODES.ONE_1U],
  'MOVE_1U': [INSTRUCTION_CLASSES.D8_D8, INSTRUCTION_OPCODES.MOVE_1U],
  'SAVE_1U': [INSTRUCTION_CLASSES.D8, INSTRUCTION_OPCODES.SAVE_1U],
  'DEC_1U': [INSTRUCTION_CLASSES.D8_D8, INSTRUCTION_OPCODES.DEC_1U],
  'INC_1U': [INSTRUCTION_CLASSES.D8_D8, INSTRUCTION_OPCODES.INC_1U],
  'AND_1U': [INSTRUCTION_CLASSES.D8_D8_D8, INSTRUCTION_OPCODES.AND_1U],
  'ADD_1U': [INSTRUCTION_CLASSES.D8_D8_D8, INSTRUCTION_OPCODES.ADD_1U],
  'SUB_1U': [INSTRUCTION_CLASSES.D8_D8_D8, INSTRUCTION_OPCODES.SUB_1U],
  'GREATER_THAN_1U': [INSTRUCTION_CLASSES.D8_D8_D8, INSTRUCTION_OPCODES.GREATER_THAN_1U],
  'EQUAL_1U': [INSTRUCTION_CLASSES.D8_D8_D8, INSTRUCTION_OPCODES.EQUAL_1U],
  'EQUAL_ZERO_1U': [INSTRUCTION_CLASSES.D8_D8, INSTRUCTION_OPCODES.EQUAL_ZERO_1U],
  'CONVERT_1U_2U': [INSTRUCTION_CLASSES.D8_D16, INSTRUCTION_OPCODES.CONVERT_1U_2U],
  'MOVE_2U': [INSTRUCTION_CLASSES.D16_D16, INSTRUCTION_OPCODES.MOVE_2U],
  'SAVE_2U': [INSTRUCTION_CLASSES.D16, INSTRUCTION_OPCODES.SAVE_2U],
  'DEC_2U': [INSTRUCTION_CLASSES.D16_D16, INSTRUCTION_OPCODES.DEC_2U],
  'INC_2U': [INSTRUCTION_CLASSES.D16_D16, INSTRUCTION_OPCODES.INC_2U],
  'ADD_2U': [INSTRUCTION_CLASSES.D16_D16_D16, INSTRUCTION_OPCODES.ADD_2U],
  'SUB_2U': [INSTRUCTION_CLASSES.D16_D16_D16, INSTRUCTION_OPCODES.SUB_2U],
  'MUL_2U': [INSTRUCTION_CLASSES.D16_D16_D16, INSTRUCTION_OPCODES.MUL_2U],
  'DIV_2U': [INSTRUCTION_CLASSES.D16_D16_D16, INSTRUCTION_OPCODES.DIV_2U],
  'ZERO_2U': [INSTRUCTION_CLASSES.D16, INSTRUCTION_OPCODES.ZERO_2U],
  'CONVERT_2U_4U': [INSTRUCTION_CLASSES.D16_D32, INSTRUCTION_OPCODES.CONVERT_2U_4U],
  'GREATER_THAN_2U': [INSTRUCTION_CLASSES.D16_D16_D8, INSTRUCTION_OPCODES.GREATER_THAN_2U],
  'EQUAL_2U': [INSTRUCTION_CLASSES.D16_D16_D8, INSTRUCTION_OPCODES.EQUAL_2U],
  'EQUAL_ZERO_2U': [INSTRUCTION_CLASSES.D16_D8, INSTRUCTION_OPCODES.EQUAL_ZERO_2U],
  'ZERO_4U': [INSTRUCTION_CLASSES.D32, INSTRUCTION_OPCODES.ZERO_4U],
  'SAVE_4U': [INSTRUCTION_CLASSES.D32, INSTRUCTION_OPCODES.SAVE_4U],
  'MOVE_4U': [INSTRUCTION_CLASSES.D32_D32, INSTRUCTION_OPCODES.MOVE_4U],
  'ADD_4U': [INSTRUCTION_CLASSES.D32_D32_D32, INSTRUCTION_OPCODES.ADD_4U],
  'MUL_4U': [INSTRUCTION_CLASSES.D32_D32_D32, INSTRUCTION_OPCODES.MUL_4U],
  'DIV_4U': [INSTRUCTION_CLASSES.D32_D32_D32, INSTRUCTION_OPCODES.DIV_4U],
  'REMINDER_4U': [INSTRUCTION_CLASSES.D32_D32_D32, INSTRUCTION_OPCODES.REMINDER_4U],
  'CONVERT_4U_2U': [INSTRUCTION_CLASSES.D32_D16, INSTRUCTION_OPCODES.CONVERT_4U_2U],
  'BRANCH_FALSE': [INSTRUCTION_CLASSES.D8_BR, INSTRUCTION_OPCODES.BRANCH_FALSE],
  'BRANCH_TRUE': [INSTRUCTION_CLASSES.D8_BR, INSTRUCTION_OPCODES.BRANCH_TRUE],
  'BRANCH': [INSTRUCTION_CLASSES.BR],
};

const bitStreamToByteArray = (bitStream) => {
  const byteArray = [];
  for (let i = 0; i < bitStream.length; i += 8) {
    byteArray.push(parseInt(bitStream.substr(i, 8).split('').reverse().join(''), 2));
  }

  return byteArray;
};

const numberToBitString = (number, bits) => number.toString(2).padStart(bits, '0').split('').reverse().join('');

// EAS = 00, slot = 1 (constants data segment)
const DATA_SEGMENT_OBJ_SELECTOR = '001000';

const encodeOperand = (operand, varsInfo, lineNo) => {
  if (operand.match(/^[01_]+$/)) {
    return operand.replaceAll(/_/g, '');
  }

  const [, arrayName, index] = operand.match(/^([\w\$]+)\[([\w\$]+)\]$/) || [];
  if (arrayName && index) {
    if (!varsInfo.vars[index]) {
      throw new Error(`Variable ${index} not found, line ${lineNo}`);
    }

    const indexOffset = varsInfo.vars[index].offset;
    const indexBitstream = indexOffset > 0x8F
      ? (INSTRUCTION_DATA_REF_DISPL_LEN.BIT16 + numberToBitString(indexOffset, 16))
      : (INSTRUCTION_DATA_REF_DISPL_LEN.BIT7 + numberToBitString(indexOffset, 7));

    if (arrayName === '$data') {
      return INSTRUCTION_DATA_REF_DISPL_CTRL.STATIC_VECTOR
        + INSTRUCTION_DATA_REF_SEGMENT_CTRL.DIRECT_SHORT
        + INSTRUCTION_DATA_REF_DISPL_BASE_LEN.BIT0
        + DATA_SEGMENT_OBJ_SELECTOR
        + INSTRUCTION_DATA_REF_DISPL_INDIRECT_TYPE.INTRASEGMENT
        + indexBitstream;
    }

    if (!varsInfo.vars[arrayName]) {
      throw new Error(`Variable ${arrayName} not found, line ${lineNo}`);
    }

    return INSTRUCTION_DATA_REF_DISPL_CTRL.STATIC_VECTOR
      + INSTRUCTION_DATA_REF_SEGMENT_CTRL.DIRECT_SHORT
      + INSTRUCTION_DATA_REF_DISPL_BASE_LEN.BIT16
      + DATA_SEGMENT_OBJ_SELECTOR
      + numberToBitString(varsInfo.vars[arrayName].offset, 16)
      + INSTRUCTION_DATA_REF_DISPL_INDIRECT_TYPE.INTRASEGMENT
      + indexBitstream;
  }

  if (!varsInfo.vars[operand]) {
    throw new Error(`Variable ${operand} not found, line ${lineNo}`);
  }

  if (varsInfo.vars[operand].offset <= 0x8F) {
    return INSTRUCTION_DATA_REF_DISPL_CTRL.SCALAR
      + INSTRUCTION_DATA_REF_SEGMENT_CTRL.DIRECT_SHORT
      + INSTRUCTION_DATA_REF_DISPL_LEN.BIT7
      + DATA_SEGMENT_OBJ_SELECTOR
      + numberToBitString(varsInfo.vars[operand].offset, 7);
  }

  return INSTRUCTION_DATA_REF_DISPL_CTRL.SCALAR
    + INSTRUCTION_DATA_REF_SEGMENT_CTRL.DIRECT_SHORT
    + INSTRUCTION_DATA_REF_DISPL_LEN.BIT16
    + DATA_SEGMENT_OBJ_SELECTOR
    + numberToBitString(varsInfo.vars[operand].offset, 16);
};

const encode3order = (operands, varsInfo, lineNo) => {
  if (operands[0] === '$st0') {
    if (operands[1] === '$st1') {
      return operands[2] === '$st2' ? INSTRUCTION_FORMATS.STK1_STK2_STK3 : `${INSTRUCTION_FORMATS.STK1_STK2_REF1}${encodeOperand(operands[2], varsInfo, lineNo)}`;
    }

    if (operands[2] === '$st0') {
        return `${INSTRUCTION_FORMATS.STK1_REF1_STK1}${encodeOperand(operands[1], varsInfo, lineNo)}`;
    }

    return operands[1] === operands[2]
      ? `${INSTRUCTION_FORMATS.STK1_REF1_REF1}${encodeOperand(operands[1], varsInfo, lineNo)}`
      : `${INSTRUCTION_FORMATS.STK1_REF1_REF2}${encodeOperand(operands[1], varsInfo, lineNo)}${encodeOperand(operands[2], varsInfo, lineNo)}`;
  }

  if (operands[1] === '$st0') {
    if (operands[0] === '$st1') {
      return operands[2] === '$st2' ? INSTRUCTION_FORMATS.STK2_STK1_STK3 : `${INSTRUCTION_FORMATS.STK2_STK1_REF1}${encodeOperand(operands[2], varsInfo, lineNo)}`;
    }

    if (operands[2] === '$st0') {
      return `${INSTRUCTION_FORMATS.REF1_STK1_STK1}${encodeOperand(operands[0], varsInfo, lineNo)}`;
    }

    return operands[0] === operands[2]
      ? `${INSTRUCTION_FORMATS.REF1_STK1_REF1}${encodeOperand(operands[0], varsInfo, lineNo)}`
      : `${INSTRUCTION_FORMATS.REF1_STK1_REF2}${encodeOperand(operands[0], varsInfo, lineNo)}${encodeOperand(operands[2], varsInfo, lineNo)}`;
  }

  if (operands[2] === '$st0') {
    return `${INSTRUCTION_FORMATS.REF1_REF2_STK1}${encodeOperand(operands[0], varsInfo, lineNo)}${encodeOperand(operands[1], varsInfo, lineNo)}`;
  }

  if (operands[1] === operands[2]) {
    return `${INSTRUCTION_FORMATS.REF1_REF2_REF2}${encodeOperand(operands[0], varsInfo, lineNo)}${encodeOperand(operands[1], varsInfo, lineNo)}`;
  }

  if (operands[0] === operands[2]) {
    return `${INSTRUCTION_FORMATS.REF1_REF2_REF1}${encodeOperand(operands[0], varsInfo, lineNo)}${encodeOperand(operands[1], varsInfo, lineNo)}`;
  }

  return `${INSTRUCTION_FORMATS.REF1_REF2_REF3}${encodeOperand(operands[0], varsInfo, lineNo)}${encodeOperand(operands[1], varsInfo, lineNo)}${encodeOperand(operands[2], varsInfo, lineNo)}`;
}

const encodeOperands = (operands, varsInfo, lineNo) => {
  switch (operands.length) {
    case 3:
      return encode3order(operands, varsInfo, lineNo);

    case 1:
      if (operands[0] === '$st0') {
        return INSTRUCTION_FORMATS.STK1;
      }

      return `${INSTRUCTION_FORMATS.REF1}${encodeOperand(operands[0], varsInfo, lineNo)}`;

    case 2:
      if (operands[0] === '$st0' && operands[1] === '$st0') {
        return INSTRUCTION_FORMATS.STK1_STK1;
      }

      if (operands[1] === '$st0') {
        return `${INSTRUCTION_FORMATS.REF1_STK1}${encodeOperand(operands[0], varsInfo, lineNo)}`;
      }

      if (operands[0] === '$st0') {
        return `${INSTRUCTION_FORMATS.STK1_REF1}${encodeOperand(operands[1], varsInfo, lineNo)}`;
      }

      return operands[0] === operands[1]
        ? `${INSTRUCTION_FORMATS.REF1_REF1}${encodeOperand(operands[0], varsInfo, lineNo)}`
        : `${INSTRUCTION_FORMATS.REF1_REF2}${encodeOperand(operands[0], varsInfo, lineNo)}${encodeOperand(operands[1], varsInfo, lineNo)}`;

    case 0:
      return '';

    default:
      throw new Error('Invalid operand count');
  }
};

const compileInstruction = (iclass, operands = '', opcode = '') => {
  return `${iclass}${operands}${opcode}`;
};

const compileBranchInstruction = (baseOffset, iclass, opcode, operands, varsInfo, refs, lineNo) => {
  const refPlaceholder = '0000000000000000';

  if (iclass === INSTRUCTION_CLASSES.BR) {
    // no operands, just a label
    const instrOffset = iclass.length + INSTRUCTION_DATA_REF_BRANCH_TYPE.ABSOLUTE.length;
    refs.push({ label: operands[0], offset: baseOffset + instrOffset });
    return `${iclass}${INSTRUCTION_DATA_REF_BRANCH_TYPE.ABSOLUTE}${refPlaceholder}${opcode}`;
  }

  // stack as operand
  if (operands[0] === '$st0') {
    const instrOffset = iclass.length + INSTRUCTION_FORMATS.STK1.length + INSTRUCTION_DATA_REF_BRANCH_TYPE.ABSOLUTE.length;
    refs.push({ label: operands[1], offset: baseOffset + instrOffset });
    return `${iclass}${INSTRUCTION_FORMATS.STK1}${INSTRUCTION_DATA_REF_BRANCH_TYPE.ABSOLUTE}${refPlaceholder}${opcode}`;
  }

  // variable as operand
  const encodedOperand = encodeOperand(operands[0], varsInfo, lineNo);
  const instrOffset = iclass.length + INSTRUCTION_FORMATS.REF1.length + encodedOperand.length + INSTRUCTION_DATA_REF_BRANCH_TYPE.ABSOLUTE.length;
  refs.push({ label: operands[1], offset: baseOffset + instrOffset });
  return `${iclass}${INSTRUCTION_FORMATS.REF1}${encodedOperand}${INSTRUCTION_DATA_REF_BRANCH_TYPE.ABSOLUTE}${refPlaceholder}${opcode}`;
};

export const compile = (sourceCode) => {
  const lines = sourceCode.split('\n').map((x, i) => ({ line: x.replace(/#.*/, '').trim(), idx: i + 1 })).filter((line) => line.line.length);
  const stackInfo = {};
  const dataInfo = {};
  let instructionStart = 0;

  // Parse directives first
  for (let i = 0; i < lines.length; i++) {
    const { line } = lines[i];
    if (line[0] !== '.') {
      instructionStart = i;
      break;
    }

    const directiveName = (line.match(/^\.(\w+)\s*\{$/) || [])[1];
    if (!directiveName) {
      throw new Error('Invalid directive');
    }

    let content = '';
    i++; // Move to next line
    while (i < lines.length && lines[i].line !== '}') {
      content += lines[i].line + '\n';
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
          const varMatch = line.match(/(\w+)\s*=\s*\{\s*size\s*=\s*(\d+)(?:,\s*data\s*=\s*\[([^\]]*)\])?\s*\}/);
          if (!varMatch) {
            throw new Error(`Invalid var definition: ${line}`);
          }

          const name = varMatch[1];
          const size = parseInt(varMatch[2]);
          const specifiedData = varMatch[3]?.split(',').map((x) => parseInt(x.trim(), 16)).filter(x => !isNaN(x)) || [];
          if (specifiedData.length > size) {
            throw new Error(`Data for ${name} exceeds specified size`);
          }

          const data = [...specifiedData, ...Array(size - specifiedData.length).fill(0)];
          dataInfo.vars[name] = { size, data, offset };
          offset += size;

          // need to align to 16-bit boundary
          if (offset % 2 !== 0) {
            offset++;
          }
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
    const { line, idx } = lines[i];
    if (line.endsWith(':')) {
      labels[line.slice(0, -1)] = offset;
      continue;
    }

    const [instruction, ...operands] = line.split(' ');
    const [iclass, opcode = ''] = INSTRUCTION_ENCODINGS[instruction] || [];
    if (!iclass) {
      throw new Error(`Unknown instruction: ${instruction}`);
    }

    const isBranch = [INSTRUCTION_CLASSES.D8_BR, INSTRUCTION_CLASSES.BR].includes(iclass);
    const encodedInstruction = isBranch
      ? compileBranchInstruction(offset, iclass, opcode, operands, dataInfo, refs, idx)
      : compileInstruction(iclass, encodeOperands(operands, dataInfo, idx), opcode);

    bitStream += encodedInstruction;
    instructionsMap.set(offset, line);
    offset += encodedInstruction.length;
  }

  // fix references to labels
  for (const { label, offset } of refs) {
    const labelAddress = labels[label];
    if (labelAddress === undefined) {
      throw new Error(`Label not found: ${label}`);
    }

    const relOffset = offset - INSTRUCTION_HEADER_SIZE * 8;
    const branchRef = numberToBitString(labelAddress, 16);
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
