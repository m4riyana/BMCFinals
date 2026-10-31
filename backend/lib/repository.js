'use strict';
class MemoryRepository {
  constructor(seed = {}) { this.data = new Map(Object.entries(structuredClone(seed))); this.tail = Promise.resolve(); }
  async get(path) { return structuredClone(this.data.get(path) || null); }
  async set(path,value) { return this.transaction(tx=>tx.set(path,value)); }
  filter(data, collection, filters = {}) {
    return [...data.entries()].filter(([key])=>key.startsWith(`${collection}/`) && key.split('/').length===2).map(([,value])=>structuredClone(value))
      .filter(value=>(!filters.active || value.isActive) && (!filters.uid || value.uid===filters.uid) && (!filters.categoryId || value.categoryId===filters.categoryId))
      .sort((a,b)=>collection==='orders' ? (b.createdAt || '').localeCompare(a.createdAt || '') : 0).slice(0,filters.limit||500);
  }
  async list(collection, filters) { return this.filter(this.data,collection,filters); }
  transaction(fn) {
    const run = this.tail.then(async()=>{ const staged = new Map(structuredClone([...this.data])); const result = await fn({get:async path=>structuredClone(staged.get(path)||null), query:async (collection,filters)=>this.filter(staged,collection,filters), set:(path,value)=>staged.set(path,structuredClone(value)), delete:path=>staged.delete(path)});this.data=staged;return result; });
    this.tail=run.catch(()=>{}); return run;
  }
}
module.exports = {MemoryRepository};
