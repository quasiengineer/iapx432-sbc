export class BaseObject {
  constructor(ref, { directoryObjectTable } = {}) {
    this.ref = ref;
    this.directoryObjectTable = directoryObjectTable;
  }
}