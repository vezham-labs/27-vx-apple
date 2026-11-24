// Ark: runs in an extension's background before the extension's own code. It fills in what
// WebKit's extension runtime lacks for extensions built for Chrome, and works around two WebKit
// problems in service workers. Plain objects only: wrapping WebKit's API objects in a Proxy breaks
// message delivery.
(() => {
  if (globalThis.__arkCompat) return;
  globalThis.__arkCompat = true;
  const isWorker = typeof window === 'undefined';
  const roots = [globalThis.chrome, globalThis.browser].filter((r, i, all) => r && all.indexOf(r) === i);
  // WebKit may drop a namespace's JS wrapper (and anything added to it) and hand out a fresh one, so
  // keep a reference to every object patched here.
  const kept = [];
  const keep = (o) => { kept.push(o); return o; };
  globalThis.__arkCompatKept = kept;

  // Chrome exposes these well-known symbols to extension bundles (Bitwarden uses them as
  // disposal keys); WebKit may not. Keep the fallbacks stable across extension contexts.
  for (const name of ['dispose', 'asyncDispose']) {
    if (Symbol[name] === undefined) {
      try { Object.defineProperty(Symbol, name, { value: Symbol.for(`Symbol.${name}`) }); } catch (e) {}
    }
  }
  // WebKit removed requestIdleCallback; some password-manager extensions require it at startup.
  if (typeof globalThis.requestIdleCallback !== 'function') {
    const idle = new Map();
    let idleId = 0;
    globalThis.requestIdleCallback = (callback) => {
      const id = ++idleId;
      idle.set(id, setTimeout(() => {
        if (!idle.delete(id)) return;
        const start = Date.now();
        callback({ didTimeout: false, timeRemaining: () => Math.max(0, 50 - (Date.now() - start)) });
      }, 1));
      return id;
    };
    globalThis.cancelIdleCallback = (id) => {
      const timer = idle.get(id);
      if (timer !== undefined) { idle.delete(id); clearTimeout(timer); }
    };
  }

  const event = () => {
    const listeners = new Set();
    return {
      addListener(fn) { listeners.add(fn); },
      removeListener(fn) { listeners.delete(fn); },
      hasListener(fn) { return listeners.has(fn); },
      hasListeners() { return listeners.size > 0; },
    };
  };
  const unsupported = (name) => () => Promise.reject(new Error(`${name} isn't supported in Ark`));
  const resolves = (value) => () => Promise.resolve(value);

  // Namespaces WebKit doesn't have. Events never fire; calls either answer the way a browser with
  // nothing to report would, or reject.
  const namespaces = {
    // Real macOS notifications, through Ark (ExtensionBridges.swift). Clicks bring Ark forward;
    // onClicked/onClosed don't fire yet.
    notifications: () => ({
      create: (...args) => {
        const cb = typeof args[args.length - 1] === 'function' ? args.pop() : null;
        const id = typeof args[0] === 'string' ? args[0] : `ark-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
        const o = (typeof args[0] === 'string' ? args[1] : args[0]) || {};
        const p = bridge('ark.notifications', { action: 'create', id, title: o.title || '', message: o.message || o.contextMessage || '' }).then(() => id);
        if (cb) p.then(cb, () => cb(id));
        return p;
      },
      update: resolves(false),
      clear: (id, cb) => { const p = bridge('ark.notifications', { action: 'clear', id }).then(() => true, () => false); if (cb) p.then(cb); return p; },
      getAll: (cb) => { const p = Promise.resolve({}); if (cb) p.then(cb); return p; },
      getPermissionLevel: (cb) => { const p = Promise.resolve('granted'); if (cb) p.then(cb); return p; },
      onClicked: event(), onClosed: event(), onButtonClicked: event(), onShowSettings: event(), onPermissionLevelChanged: event(),
    }),
    idle: () => ({
      queryState: resolves('active'), setDetectionInterval() {}, getAutoLockDelay: resolves(0),
      onStateChanged: event(),
    }),
    management: (previous = {}, root = globalThis.chrome || globalThis.browser) => managementAPI(root, previous),
    privacy: () => {
      const setting = () => ({ get: resolves({ value: false, levelOfControl: 'not_controllable' }), set: resolves(undefined), clear: resolves(undefined), onChange: event() });
      return { services: { passwordSavingEnabled: setting(), autofillAddressEnabled: setting(), autofillCreditCardEnabled: setting(), autofillEnabled: setting() }, network: {}, websites: {} };
    },
    // Saved to the Downloads folder by Ark and listed in its Downloads panel. blob: URLs are read
    // here first, since only this extension can read them.
    downloads: () => ({
      download: (o = {}, cb) => {
        const p = (async () => {
          let url = o.url || '';
          if (url.startsWith('blob:')) {
            const buf = await (await fetch(url)).arrayBuffer();
            if (buf.byteLength > 50 * 1024 * 1024) throw new Error('downloads.download: blobs over 50 MB aren\'t supported in Ark yet');
            let bin = '';
            const bytes = new Uint8Array(buf);
            for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
            url = 'data:application/octet-stream;base64,' + btoa(bin);
          }
          return bridge('ark.downloads', { action: 'download', url, filename: o.filename || '' });
        })();
        if (cb) p.then(cb, () => cb(undefined));
        return p;
      },
      search: resolves([]), open: unsupported('downloads.open'),
      onCreated: event(), onChanged: event(), onErased: event(), onDeterminingFilename: event(),
    }),
    // A hidden extension page Ark keeps for the extension (ExtensionOffscreen.swift).
    offscreen: () => ({
      createDocument: (p) => offscreenCall('create', p && p.url).then(() => undefined),
      closeDocument: () => offscreenCall('close').then(() => undefined),
      hasDocument: () => offscreenCall('has').then((url) => !!url),
      Reason: offscreenReasons,
    }),
    // The side panel is Ark's right panel. open() shows it; openPanelOnActionClick makes the toolbar
    // button open it, as in Chrome.
    sidePanel: () => ({
      setOptions: resolves(undefined),
      getOptions: resolves({}),
      setPanelBehavior: (b = {}) => bridge('ark.sidepanel', { action: 'behavior', openPanelOnActionClick: !!b.openPanelOnActionClick }).then(() => undefined),
      getPanelBehavior: () => bridge('ark.sidepanel', { action: 'getBehavior' }),
      open: () => bridge('ark.sidepanel', { action: 'open' }).then(() => undefined),
    }),
    // Ark pin folders are not extension tab groups. Report no groups and reject mutating APIs.
    tabGroups: () => ({
      TAB_GROUP_ID_NONE: -1,
      Color: Object.fromEntries(['GREY', 'BLUE', 'RED', 'YELLOW', 'GREEN', 'PINK', 'PURPLE', 'CYAN', 'ORANGE'].map(c => [c, c.toLowerCase()])),
      query: resolves([]), get: unsupported('tabGroups.get'), update: unsupported('tabGroups.update'), move: unsupported('tabGroups.move'),
      onCreated: event(), onUpdated: event(), onMoved: event(), onRemoved: event(),
    }),
    // Ark does not expose Chrome's DevTools protocol to extensions. Explicit rejections let
    // extensions disable debugger-dependent features instead of failing on a missing namespace.
    debugger: () => ({
      attach: unsupported('debugger.attach'), detach: unsupported('debugger.detach'),
      sendCommand: unsupported('debugger.sendCommand'), getTargets: resolves([]),
      onEvent: event(), onDetach: event(),
    }),
    identity: () => ({ launchWebAuthFlow: (details = {}, cb) => {
      const p = bridge('ark.identity', { url: String(details.url || ''), interactive: !!details.interactive,
        timeout: details.timeoutMsForNonInteractive || 5000 });
      if (cb) p.then(cb, (e) => { try { chrome.runtime.lastError = e; } catch (_) {} cb(undefined); });
      return p;
    }, getRedirectURL: (p = '') => `https://${chrome.runtime.id}.chromiumapp.org/${p}`, onSignInChanged: event() }),
    contentSettings: () => ({}),
  };
  // Events missing from namespaces WebKit does have.
  const events = {
    runtime: ['onStartup', 'onInstalled', 'onSuspend', 'onSuspendCanceled', 'onUpdateAvailable', 'onConnectExternal', 'onMessageExternal', 'onRestartRequired'],
    tabs: ['onCreated', 'onRemoved', 'onUpdated', 'onActivated', 'onReplaced', 'onHighlighted', 'onMoved', 'onAttached', 'onDetached', 'onZoomChange'],
    windows: ['onCreated', 'onRemoved', 'onFocusChanged', 'onBoundsChanged'],
    webNavigation: ['onCreatedNavigationTarget', 'onBeforeNavigate', 'onCommitted', 'onCompleted', 'onDOMContentLoaded', 'onErrorOccurred', 'onHistoryStateUpdated', 'onReferenceFragmentUpdated', 'onTabReplaced'],
    webRequest: ['onAuthRequired', 'onBeforeRedirect', 'onBeforeRequest', 'onBeforeSendHeaders', 'onSendHeaders', 'onHeadersReceived', 'onResponseStarted', 'onCompleted', 'onErrorOccurred'],
    action: ['onClicked', 'onUserSettingsChanged'],
    contextMenus: ['onClicked'],
    alarms: ['onAlarm'],
    permissions: ['onAdded', 'onRemoved'],
    commands: ['onCommand'],
  };
  const offscreenCall = (action, url) => chrome.runtime.sendNativeMessage('ark.offscreen', { action, url });
  const bridge = (name, body) => chrome.runtime.sendNativeMessage(name, body);
  function managementAPI(root, previous = {}) {
    const call = (action, id, callback) => {
      const message = { action };
      if (id !== undefined) message.id = String(id);
      const promise = root.runtime.sendNativeMessage('ark.management', message);
      if (typeof callback !== 'function') return promise;
      promise.then(callback, (error) => {
        try { root.runtime.lastError = { message: String(error && error.message || error) }; } catch (_) {}
        try { callback(undefined); } finally {
          setTimeout(() => { try { root.runtime.lastError = undefined; } catch (_) {} }, 0);
        }
      });
      return undefined;
    };
    return {
      getSelf: (callback) => call('getSelf', undefined, callback),
      getAll: (callback) => call('getAll', undefined, callback),
      get: (id, callback) => call('get', id, callback),
      onInstalled: previous.onInstalled || event(), onUninstalled: previous.onUninstalled || event(),
      onEnabled: previous.onEnabled || event(), onDisabled: previous.onDisabled || event(),
    };
  }
  const offscreenReasons = Object.fromEntries(['TESTING', 'AUDIO_PLAYBACK', 'IFRAME_SCRIPTING', 'DOM_SCRAPING', 'BLOBS', 'DOM_PARSER',
    'USER_MEDIA', 'DISPLAY_MEDIA', 'WEB_RTC', 'CLIPBOARD', 'LOCAL_STORAGE', 'WORKERS', 'BATTERY_STATUS', 'MATCH_MEDIA', 'GEOLOCATION'].map(r => [r, r]));
  // Constants and small helpers Chrome has on namespaces WebKit does provide. Extensions read some of
  // them at startup (chrome.offscreen.Reason.CLIPBOARD, chrome.scripting.ExecutionWorld.MAIN).
  const extras = {
    // Only the offscreen document is reported; other contexts aren't tracked.
    runtime: { getContexts: (filter = {}) => {
      const types = filter.contextTypes;
      if (types && !types.includes('OFFSCREEN_DOCUMENT')) return Promise.resolve([]);
      return offscreenCall('has').then((url) => url ? [{ contextType: 'OFFSCREEN_DOCUMENT', documentUrl: url, documentOrigin: new URL(url).origin,
        contextId: 'ark-offscreen', tabId: -1, windowId: -1, frameId: -1, incognito: false }] : [], () => []);
    } },
    scripting: { ExecutionWorld: { ISOLATED: 'ISOLATED', MAIN: 'MAIN' } },
    identity: { AccountStatus: Object.freeze({ SYNC: 'SYNC', ANY: 'ANY' }) },
    tabs: { TAB_ID_NONE: -1, TAB_INDEX_NONE: -1 },
    windows: { WINDOW_ID_NONE: -1, WINDOW_ID_CURRENT: -2 },
    offscreen: { Reason: offscreenReasons },
  };
  const missing = [];
  for (const root of roots) {
    for (const [name, make] of Object.entries(namespaces)) {
      if (name === 'management') {
        const previous = root[name] || {};
        const ours = keep(make(previous, root));
        try { Object.defineProperty(root, name, { value: ours, configurable: true, writable: true }); }
        catch (e) { try { Object.assign(previous, ours); } catch (e2) {} }
        missing.push('management (bridged)');
      } else if (root[name] === undefined) {
        try { root[name] = keep(make()); missing.push(name); } catch (e) {}
      } else if (name === 'sidePanel') {
        // WebKit has its own chrome.sidePanel, which Ark can't show: route its calls to Ark's panel.
        const ours = keep(make());
        try { Object.defineProperty(root, name, { value: ours, configurable: true, writable: true }); }
        catch (e) { try { Object.assign(root[name], ours); } catch (e2) {} }
        missing.push('sidePanel (replaced)');
      }
    }
    for (const [ns, names] of Object.entries(events)) {
      const target = root[ns];
      if (!target) continue;
      keep(target);
      for (const name of names) {
        if (target[name] === undefined) {
          try { target[name] = event(); missing.push(`${ns}.${name}`); } catch (e) {}
        }
      }
    }
    for (const [ns, values] of Object.entries(extras)) {
      const target = root[ns];
      if (!target) continue;
      keep(target);
      for (const [name, value] of Object.entries(values)) {
        if (target[name] === undefined) {
          try { target[name] = value; missing.push(`${ns}.${name}`); } catch (e) {}
        }
      }
    }
    // Chrome returns an empty string for getMessage(""); WebKit throws. uBlock Origin asks for
    // every bare aria-label this way while loading its popup, so one empty lookup can stop all its UI.
    const i18n = root.i18n;
    if (i18n && typeof i18n.getMessage === 'function') {
      const original = i18n.getMessage.bind(i18n);
      const getMessage = (name, ...args) => name === '' ? '' : original(name, ...args);
      try { Object.defineProperty(i18n, 'getMessage', { value: getMessage, configurable: true, writable: true }); }
      catch (e) { try { i18n.getMessage = getMessage; } catch (e2) {} }
      keep(i18n);
    }
    if (root.storage && root.storage.managed === undefined) {
      try {
        // Chrome's callback form too: Grammarly passes a callback and waits for it (timing out otherwise).
        const answer = (value) => (...args) => { const cb = args.find(a => typeof a === 'function'); if (cb) setTimeout(() => cb(value)); return Promise.resolve(value); };
        keep(root.storage).managed = { get: answer({}), getBytesInUse: answer(0), onChanged: event() };
        missing.push('storage.managed');
      } catch (e) {}
    }
    // Chrome exposes change events on each storage area as well as on storage itself.
    if (root.storage?.onChanged && typeof root.storage.onChanged.addListener === 'function') {
      for (const area of ['local', 'sync', 'session']) {
        const target = root.storage[area];
        if (!target || target.onChanged !== undefined) continue;
        const listeners = new Set();
        try {
          keep(target).onChanged = {
            addListener(fn) { if (typeof fn === 'function') listeners.add(fn); },
            removeListener(fn) { listeners.delete(fn); },
            hasListener(fn) { return listeners.has(fn); },
            hasListeners() { return listeners.size > 0; },
          };
          root.storage.onChanged.addListener((changes, areaName) => {
            if (areaName !== area) return;
            for (const fn of [...listeners]) { try { fn(changes); } catch (e) { setTimeout(() => { throw e; }); } }
          });
          missing.push(`storage.${area}.onChanged`);
        } catch (e) {}
      }
    }
  }
  // Permissions Ark provides itself (above) aren't ones WebKit knows: asking about them throws
  // ("'downloads' is not a valid permission"), which stopped FireShot saving. Answer yes for them,
  // and pass the rest to WebKit.
  const bridged = ['downloads', 'notifications', 'sidePanel'];
  for (const root of roots) {
    const perms = root.permissions;
    if (!perms) continue;
    for (const fn of ['contains', 'request']) {
      const original = typeof perms[fn] === 'function' ? perms[fn].bind(perms) : null;
      if (!original) continue;
      const wrapped = (p = {}, cb) => {
        const asked = Array.isArray(p.permissions) ? p.permissions : [];
        const rest = asked.filter((x) => !bridged.includes(x));
        const origins = Array.isArray(p.origins) ? p.origins : [];
        let result;
        if (!rest.length && !origins.length) result = Promise.resolve(true);
        else {
          try { result = Promise.resolve(original({ ...p, permissions: rest })); } catch (e) { result = Promise.reject(e); }
        }
        if (cb) { result.then((v) => cb(!!v), () => cb(false)); return undefined; }
        return result;
      };
      try { Object.defineProperty(perms, fn, { value: wrapped, configurable: true, writable: true }); }
      catch (e) { try { perms[fn] = wrapped; } catch (e2) {} }
    }
    try { keep(perms); } catch (e) {}
  }
  globalThis.__arkCompatMissing = missing;

  // These are Chrome builds of the extensions, and some decide what they're running in from the user
  // agent (Bitwarden's device type is null without " Chrome/", and its background throws). Inside the
  // extension only, the user agent says Chrome; websites still see Ark's own.
  const ua = globalThis.navigator && navigator.userAgent;
  if (ua && !ua.includes(' Chrome/')) {
    const chromeUA = ua.replace(/ Version\/[\d.]+/, '').replace(/ Safari\/[\d.]+/, '') + ' Chrome/142.0.0.0 Safari/537.36';
    try { Object.defineProperty(Object.getPrototypeOf(navigator), 'userAgent', { get: () => chromeUA, configurable: true }); } catch (e) {}
    try { Object.defineProperty(Object.getPrototypeOf(navigator), 'vendor', { get: () => 'Google Inc.', configurable: true }); } catch (e) {}
  }

  // Copying from an extension page without a click (Chrome allows it with the clipboardWrite
  // permission, e.g. Paper Snapshot's offscreen page). WebKit refuses document.execCommand('copy')
  // there, so when it does, the page's own copy handler runs on a stand-in clipboard and Ark
  // writes what it set (ExtensionOffscreen.swift, "ark.clipboard").
  if (!isWorker && globalThis.document && typeof document.execCommand === 'function') {
    const execCommand = document.execCommand;
    document.execCommand = function (command, ...rest) {
      const done = execCommand.call(this, command, ...rest);
      if (done || String(command).toLowerCase() !== 'copy' || typeof DataTransfer !== 'function') return done;
      try {
        const data = new DataTransfer();
        const copy = new ClipboardEvent('copy', { clipboardData: data, bubbles: true, cancelable: true });
        (document.activeElement || document).dispatchEvent(copy);
        const items = {};
        for (const type of data.types) items[type] = data.getData(type);
        if (!Object.keys(items).length) return false;
        const sent = chrome.runtime.sendNativeMessage('ark.clipboard', { items });
        if (sent && sent.catch) sent.catch(() => {});
        return true;
      } catch (e) { return false; }
    };
  }

  if (!isWorker) return;

  // navigator.locks, inside the worker. WebKit's own goes over IPC to a lock registry that can reject
  // a service worker's requests ("Received an invalid message") and leave them pending for ever.
  // Locks only need to coordinate this extension's own code, so a local implementation is enough.
  const lockQueues = new Map();   // name -> [{ mode, grant, signal, held }]
  const held = new Map();         // name -> [{ mode, clientId }]
  const tryGrant = (name) => {
    const queue = lockQueues.get(name) || [];
    let current = held.get(name) || [];
    while (queue.length) {
      const next = queue[0];
      const compatible = current.length === 0 || (next.mode === 'shared' && current.every(h => h.mode === 'shared'));
      if (!compatible) break;
      queue.shift();
      const entry = { mode: next.mode };
      current = [...current, entry];
      held.set(name, current);
      next.grant(entry);
      if (next.mode === 'exclusive') break;
    }
    if (!queue.length) lockQueues.delete(name);
  };
  const release = (name, entry) => {
    const list = (held.get(name) || []).filter(h => h !== entry);
    if (list.length) held.set(name, list); else held.delete(name);
    tryGrant(name);
  };
  const lockManager = {
    async request(name, options, callback) {
      if (typeof options === 'function') { callback = options; options = {}; }
      name = String(name);
      const mode = options.mode === 'shared' ? 'shared' : 'exclusive';
      const signal = options.signal;
      if (signal && signal.aborted) throw signal.reason ?? new DOMException('The request was aborted.', 'AbortError');
      if (options.steal) {
        held.delete(name);
      }
      const current = held.get(name) || [];
      const free = current.length === 0 || (mode === 'shared' && current.every(h => h.mode === 'shared'));
      const queued = (lockQueues.get(name) || []).length > 0;
      if (options.ifAvailable && (!free || queued) && !options.steal) return callback(null);
      const entry = await new Promise((resolve, reject) => {
        const request = { mode, grant: resolve };
        if (!lockQueues.has(name)) lockQueues.set(name, []);
        lockQueues.get(name).push(request);
        if (signal) {
          signal.addEventListener('abort', () => {
            const queue = lockQueues.get(name) || [];
            const i = queue.indexOf(request);
            if (i >= 0) { queue.splice(i, 1); reject(signal.reason ?? new DOMException('The request was aborted.', 'AbortError')); }
          }, { once: true });
        }
        tryGrant(name);
      });
      try {
        return await callback({ name, mode });
      } finally {
        release(name, entry);
      }
    },
    async query() {
      const out = { held: [], pending: [] };
      for (const [name, list] of held) for (const h of list) out.held.push({ name, mode: h.mode, clientId: 'ark' });
      for (const [name, queue] of lockQueues) for (const q of queue) out.pending.push({ name, mode: q.mode, clientId: 'ark' });
      return out;
    },
  };
  try { Object.defineProperty(globalThis.navigator, 'locks', { value: lockManager, configurable: true }); } catch (e) {}

  // WebSocket, inside the worker. WebKit runs an extension's service worker on its process's main
  // thread, and opening a WebSocket there waits on that same thread: the worker freezes for good.
  // This stand-in asks Ark to open the socket and passes frames over a native-messaging port.
  const NativeWebSocket = globalThis.WebSocket;
  const toBase64 = (buffer) => {
    const bytes = new Uint8Array(buffer);
    let s = '';
    for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return btoa(s);
  };
  const fromBase64 = (text) => Uint8Array.from(atob(text), c => c.charCodeAt(0)).buffer;

  class ArkWebSocket extends EventTarget {
    static CONNECTING = 0; static OPEN = 1; static CLOSING = 2; static CLOSED = 3;
    CONNECTING = 0; OPEN = 1; CLOSING = 2; CLOSED = 3;

    constructor(url, protocols) {
      super();
      const parsed = new URL(url, location.href);
      if (parsed.protocol !== 'ws:' && parsed.protocol !== 'wss:') throw new DOMException(`The URL's scheme must be either 'ws' or 'wss'.`, 'SyntaxError');
      this.url = parsed.href;
      this.readyState = 0;
      this.protocol = '';
      this.extensions = '';
      this.bufferedAmount = 0;
      this.binaryType = 'blob';
      this.onopen = this.onmessage = this.onerror = this.onclose = null;
      const list = protocols === undefined ? [] : Array.isArray(protocols) ? protocols : [protocols];
      try {
        this._port = chrome.runtime.connectNative('ark.websocket');
      } catch (e) {
        queueMicrotask(() => this._fail(1006, ''));
        return;
      }
      this._port.onMessage.addListener((m) => this._received(m));
      this._port.onDisconnect.addListener(() => { if (this.readyState !== 3) this._fail(1006, ''); });
      this._port.postMessage({ type: 'open', url: this.url, protocols: list.map(String) });
    }

    _emit(type, init) {
      const e = type === 'message' ? new MessageEvent('message', init) : type === 'close' ? new CloseEvent('close', init) : new Event(type);
      const handler = this['on' + type];
      if (typeof handler === 'function') { try { handler.call(this, e); } catch (err) { setTimeout(() => { throw err; }); } }
      this.dispatchEvent(e);
    }

    _received(m) {
      if (!m || typeof m !== 'object') return;
      if (m.type === 'open' && this.readyState === 0) {
        this.readyState = 1;
        this.protocol = m.protocol || '';
        this._emit('open');
      } else if (m.type === 'message' && this.readyState === 1) {
        let data;
        if (typeof m.text === 'string') data = m.text;
        else {
          const buffer = fromBase64(m.binary || '');
          data = this.binaryType === 'arraybuffer' ? buffer : new Blob([buffer]);
        }
        this._emit('message', { data, origin: new URL(this.url).origin });
      } else if (m.type === 'sent') {
        this.bufferedAmount = Math.max(0, this.bufferedAmount - (m.bytes || 0));
      } else if (m.type === 'error') {
        this._fail(m.code || 1006, m.reason || '');
      } else if (m.type === 'close') {
        this._closed(m.code || 1005, m.reason || '', !!m.wasClean);
      }
    }

    _fail(code, reason) {
      if (this.readyState === 3) return;
      this._emit('error');
      this._closed(code, reason, false);
    }

    _closed(code, reason, wasClean) {
      if (this.readyState === 3) return;
      this.readyState = 3;
      this.bufferedAmount = 0;
      try { this._port && this._port.disconnect(); } catch (e) {}
      this._emit('close', { code, reason, wasClean });
    }

    send(data) {
      if (this.readyState === 0) throw new DOMException('Still in CONNECTING state.', 'InvalidStateError');
      if (this.readyState !== 1) return;
      const post = (message, bytes) => { this.bufferedAmount += bytes; this._port.postMessage(message); };
      if (typeof data === 'string') post({ type: 'send', text: data }, new TextEncoder().encode(data).length);
      else if (data instanceof ArrayBuffer) post({ type: 'send', binary: toBase64(data) }, data.byteLength);
      else if (ArrayBuffer.isView(data)) post({ type: 'send', binary: toBase64(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength)) }, data.byteLength);
      else if (data instanceof Blob) {
        this.bufferedAmount += data.size;
        data.arrayBuffer().then(b => { this.bufferedAmount -= data.size; if (this.readyState === 1) post({ type: 'send', binary: toBase64(b) }, b.byteLength); });
      } else post({ type: 'send', text: String(data) }, String(data).length);
    }

    close(code, reason) {
      if (code !== undefined && code !== 1000 && (code < 3000 || code > 4999)) throw new DOMException('Invalid close code.', 'InvalidAccessError');
      if (this.readyState >= 2) return;
      this.readyState = 2;
      try { this._port.postMessage({ type: 'close', code: code ?? 1000, reason: reason ?? '' }); } catch (e) { this._closed(1006, '', false); }
    }
  }
  globalThis.__arkNativeWebSocket = NativeWebSocket;
  globalThis.WebSocket = ArkWebSocket;
})();
