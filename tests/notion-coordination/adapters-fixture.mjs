export const SOURCE = '10000000-0000-4000-8000-000000000001';
export const PAGE = '10000000-0000-4000-8000-000000000002';
export const BLOCK = '10000000-0000-4000-8000-000000000003';
const clone = value => structuredClone(value);
export const text = value => [{ type: 'text', text: { content: value }, annotations: { color: 'default', bold: false }, plain_text: value }];
export const appendRoute = () => ({ projectId: 'xfit', adapterId: 'xfit-append', targets: { archive: { id: SOURCE, kind: 'data_source', stableIdProperty: '记录ID', allowedProperties: { '记录ID': 'rich_text', '名称': 'title', '本人反馈': 'rich_text' }, allowedBlocks: {}, humanProperties: ['人工批准'] } } });
export const updateRoute = () => ({ projectId: 'football', adapterId: 'owned-update', targets: { summary: { id: PAGE, kind: 'page', allowedProperties: { '工程摘要': 'rich_text' }, allowedBlocks: { [BLOCK]: 'paragraph' }, humanProperties: ['人工批准'] } } });
export const appendIntent = () => ({ operationId: 'feedback-1', kind: 'append-record', target: 'archive', record: { recordId: 'feedback-1', title: '训练反馈', body: '今天没有肘部不适。', properties: { '本人反馈': '训练感觉偏轻，具体RIR未知。' } } });

// External provider substitute. Tests observe pages/blocks via its public REST seam.
export class NotionFixture {
  constructor() {
    this.pages = new Map();
    this.blocks = new Map();
    this.source = { object: 'data_source', id: SOURCE, properties: { '记录ID': { id: 'id', type: 'rich_text' }, '名称': { id: 'title', type: 'title' }, '本人反馈': { id: 'feedback', type: 'rich_text' }, '人工批准': { id: 'approval', type: 'checkbox' } } };
    this.effects = [];
    this.markdownFlags = {};
    this.identity = { verified: true, botId: 'fixture-bot', workspaceId: 'fixture-workspace' };
    this.nextId = 10;
    this.seedPage({ object: 'page', id: PAGE, archived: false, in_trash: false, parent: { type: 'workspace', workspace: true }, properties: { '工程摘要': { type: 'rich_text', rich_text: text('原工程摘要') }, '人工批准': { type: 'checkbox', checkbox: false } } }, '人工意见保持原样\n原工程摘要');
    this.blocks.set(BLOCK, { object: 'block', id: BLOCK, parent: { type: 'page_id', page_id: PAGE }, type: 'paragraph', has_children: false, archived: false, in_trash: false, paragraph: { rich_text: text('原工程摘要'), color: 'purple' } });
  }
  seedPage(page, markdown) { this.pages.set(page.id, { page: clone(page), markdown }); }
  async verifyIdentity() { return clone(this.identity); }
  async request(method, path, body) {
    path = path.replace(/^\/v1(?=\/)/, '');
    let data;
    const response = value => ({ status: 200, data: clone(value), headers: {} });
    if (method === 'GET' && path === `/data_sources/${SOURCE}`) return response(this.source);
    if (method === 'POST' && path === `/data_sources/${SOURCE}/query`) {
      const id = body.filter?.rich_text?.equals;
      const results = [...this.pages.values()].map(entry => entry.page).filter(page => page.parent.data_source_id === SOURCE && page.properties['记录ID']?.rich_text?.map(item => item.plain_text ?? item.text?.content).join('') === id);
      return response({ object: 'list', results, has_more: false, next_cursor: null });
    }
    const pagePath = path.match(/^\/pages\/([^/]+)(\/markdown)?$/);
    if (pagePath && method === 'GET') {
      const entry = this.pages.get(pagePath[1]);
      if (!entry) return { status: 404, data: {}, headers: {} };
      return response(pagePath[2] ? { object: 'page_markdown', id: pagePath[1], markdown: entry.markdown, truncated: false, unknown_block_ids: [], ...this.markdownFlags } : entry.page);
    }
    if (method === 'POST' && path === '/pages') {
      const id = `10000000-0000-4000-8000-${String(this.nextId++).padStart(12, '0')}`;
      const properties = clone(body.properties);
      for (const value of Object.values(properties)) {
        value.type ??= Object.keys(value)[0];
        if (Array.isArray(value[value.type])) value[value.type] = value[value.type].map(item => ({ ...item, plain_text: item.text.content }));
      }
      const page = { object: 'page', id, archived: false, in_trash: false, parent: { type: 'data_source_id', data_source_id: body.parent.data_source_id }, properties };
      this.seedPage(page, body.markdown);
      this.effects.push({ method, path, body: clone(body) });
      if (this.failAfterCreate) throw new Error('response lost after provider commit');
      return response(page);
    }
    if (method === 'PATCH' && pagePath && !pagePath[2]) {
      const entry = this.pages.get(pagePath[1]);
      for (const [name, value] of Object.entries(body.properties)) {
        const type = Object.keys(value)[0];
        entry.page.properties[name] = { type, ...clone(value) };
      }
      this.effects.push({ method, path, body: clone(body) });
      return response(entry.page);
    }
    const children = path.match(/^\/blocks\/([^/]+)\/children(?:\?.*)?$/);
    if (children && method === 'GET') {
      const results = [...this.blocks.values()].filter(block => block.parent.page_id === children[1] || block.parent.block_id === children[1]);
      return response({ object: 'list', results, has_more: false, next_cursor: null });
    }
    const blockPath = path.match(/^\/blocks\/([^/]+)$/);
    if (blockPath && method === 'GET') return response(this.blocks.get(blockPath[1]));
    if (blockPath && method === 'PATCH') {
      if (this.blockUpdateStatus) return { status: this.blockUpdateStatus, data: { object: 'error' }, headers: {} };
      const block = this.blocks.get(blockPath[1]);
      const update = body[block.type];
      if (update.rich_text?.some(item => Object.hasOwn(item, 'href') || Object.hasOwn(item, 'plain_text'))) return { status: 400, data: { object: 'error' }, headers: {} };
      block[block.type] = { ...block[block.type], ...clone(update) };
      if (this.rewriteStyle && block[block.type].rich_text?.[0]) block[block.type].rich_text[0].annotations.color = 'red';
      this.effects.push({ method, path, body: clone(body) });
      return response(block);
    }
    throw new Error(`unsupported fixture endpoint: ${method} ${path}`);
  }
}
