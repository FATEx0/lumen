// Behavioural contract for the Game Updates list cache: a preloaded snapshot
// must stay instant on re-entry AND pick up games added outside this panel
// (LuaTools, the library Fixes menu, another Steam view running its own copy of
// this script). Run: node tools/test_updates_cache.js
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

class El {
  constructor(tag) {
    this.tagName = String(tag || "div").toUpperCase();
    this.childNodes = [];
    this.parentNode = null;
    this.className = "";
    this.style = {};
    this.listeners = {};
    this.id = "";
    this.title = "";
    this.value = "";
  }
  appendChild(child) {
    if (child.__fragment) {
      child.childNodes.slice().forEach((node) => this.appendChild(node));
      child.childNodes = [];
      return child;
    }
    child.parentNode = this;
    this.childNodes.push(child);
    return child;
  }
  remove() {
    if (!this.parentNode) return;
    const index = this.parentNode.childNodes.indexOf(this);
    if (index !== -1) this.parentNode.childNodes.splice(index, 1);
    this.parentNode = null;
  }
  set textContent(value) {
    this.childNodes = [];
    this._text = String(value == null ? "" : value);
  }
  get textContent() {
    return (this._text || "") + this.childNodes.map((child) => child.textContent).join("");
  }
  set innerHTML(value) { this._html = String(value || ""); }
  querySelector() { return null; }
  addEventListener(type, handler) {
    (this.listeners[type] = this.listeners[type] || []).push(handler);
  }
  click() {
    (this.listeners.click || []).forEach((handler) => handler({
      target: this, stopPropagation() {}, preventDefault() {},
    }));
  }
}

function walk(node, output = []) {
  for (const child of node.childNodes) {
    output.push(child);
    walk(child, output);
  }
  return output;
}
function cards(panel) {
  return walk(panel).filter((el) => el.className === "lumen-game-card");
}
async function settle() {
  for (let i = 0; i < 6; i += 1) await new Promise((resolve) => setImmediate(resolve));
}

function game(appid) {
  return {
    appid,
    name: "Game " + appid,
    depots: [{ depot: appid, versions: [{ gid: "100" + appid, date: 1700000000 }] }],
    // cjson encodes empty Lua arrays as objects; renderGameUpdates normalizes
    // this to [] before drawing.
    dlc_appids: {},
  };
}

function harness() {
  const fragment = fs.readFileSync(
    path.join(__dirname, "..", "lua", "menu", "07-updates-tab.js"), "utf8");
  const root = new El("html");
  const documentBody = new El("body");
  root.appendChild(documentBody);
  const state = { payload: { success: true, games: [] } };
  const calls = [];
  const window = {};
  const document = {
    body: documentBody,
    documentElement: root,
    createElement: (tag) => new El(tag),
    createDocumentFragment: () => {
      const fragmentNode = new El("#fragment");
      fragmentNode.__fragment = true;
      return fragmentNode;
    },
    getElementById: () => null,
  };
  const source = [
    "(function(){",
    "function log(){}",
    "function call(fn,args){return window.__call(fn,args||{});}",
    "function injectStyles(){}",
    "function guStrings(){return {note:'note',search:'search',none:'none',",
    "  loadFail:'load failed: ',addGame:'Add game',importFiles:'Import games',",
    "  importFilesHint:'hint'};}",
    fragment,
    // The card renderer belongs to its own fragment; the cache contract only
    // cares how many cards the list paints and whether they are rebuilt.
    "gameCard = function (g) {",
    "  var card = document.createElement('div');",
    "  card.className = 'lumen-game-card';",
    "  card.__versRef = {};",
    "  card.__testAppid = g.appid;",
    "  return card;",
    "};",
    "window.__gu = { renderGameUpdates: renderGameUpdates,",
    "  reloadGameUpdates: reloadGameUpdates,",
    "  revalidateGameUpdates: revalidateGameUpdates, guOwnList: guOwnList };",
    "})();",
  ].join("\n");
  let held = null;
  window.__call = (name, args) => {
    calls.push(name);
    if (name !== "GetGameUpdates") return Promise.resolve(JSON.stringify({ success: true }));
    if (held) {
      const pending = held;
      held = null;
      return new Promise((resolve) => { pending.release = (payload) => resolve(JSON.stringify(payload)); });
    }
    return Promise.resolve(JSON.stringify(state.payload));
  };
  vm.runInNewContext(source, {
    window, document, Promise, JSON, Error, Array, Object, String, Number, Math, Date,
    setTimeout: () => 0, clearTimeout() {}, console,
  }, { filename: "updates-cache.js" });
  return {
    state,
    calls,
    gu: window.__gu,
    newPanel() { return documentBody.appendChild(new El("div")); },
    fetches() { return calls.filter((name) => name === "GetGameUpdates").length; },
    // Holds the next list request so a slow backend answer can be resolved after
    // something else already repainted the panel.
    hold() { held = {}; return held; },
  };
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function main() {
  const h = harness();
  h.state.payload = { success: true, games: [game(111)] };

  const first = h.newPanel();
  h.gu.renderGameUpdates(first);
  await settle();
  assert(h.fetches() === 1, "the first render must load the list once");
  assert(cards(first).length === 1, "the first render must paint the loaded games");

  // Reopening without any backend change must preserve the cached DOM identity,
  // including when the backend encoded an empty Lua array as {}.
  const unchangedReopen = h.newPanel();
  h.gu.renderGameUpdates(unchangedReopen);
  const unchangedCard = cards(unchangedReopen)[0];
  await settle();
  assert(h.fetches() === 2, "an unchanged reopen still confirms the snapshot");
  assert(cards(unchangedReopen)[0] === unchangedCard,
    "backend-normalized empty arrays must not trigger an unnecessary repaint");

  // A game is added outside this panel: LuaTools, the library Fixes menu, or the
  // same script running in another Steam view.
  h.state.payload = { success: true, games: [game(111), game(222)] };

  // The overlay is closed and reopened, so the panel is a brand new element while
  // the cache survives in the injected script.
  const reopened = h.newPanel();
  h.gu.renderGameUpdates(reopened);
  assert(!reopened.textContent.includes("Loading"),
    "reopening must repaint from the snapshot instead of flashing a loading state");
  assert(cards(reopened).length === 1, "the snapshot paints before the backend answers");
  await settle();
  assert(h.fetches() === 3, "reopening must revalidate the snapshot in the background");
  assert(cards(reopened).length === 2,
    "a game added outside the panel must appear once the revalidation lands");

  // An unchanged backend answer must not rebuild the DOM under the user.
  const painted = cards(reopened)[0];
  h.gu.revalidateGameUpdates();
  await settle();
  assert(h.fetches() === 4, "an explicit revalidation always asks the backend");
  assert(cards(reopened)[0] === painted, "an unchanged list must not be repainted");

  // Every backend field that can affect a card must participate in the
  // fingerprint, not only the appid and manifest gid. A source marker and a
  // build date can change while the game set stays the same.
  const changedGame = game(111);
  changedGame.fromLuaFile = true;
  changedGame.metadataAvailable = true;
  changedGame.depots[0].versions[0].date += 1;
  const beforeVisibleChange = cards(reopened)[0];
  h.state.payload = { success: true, games: [changedGame, game(222)] };
  h.gu.revalidateGameUpdates();
  await settle();
  assert(cards(reopened)[0] !== beforeVisibleChange,
    "a visible metadata or build change must repaint an otherwise unchanged game");

  // A subpage (Advanced, creator, import review) owns the panel: a revalidation
  // must never paint the list over it.
  h.gu.guOwnList(null);
  h.state.payload = { success: true, games: [game(111), game(222), game(333)] };
  const before = h.fetches();
  h.gu.revalidateGameUpdates();
  await settle();
  assert(h.fetches() === before, "a revalidation is pointless while a subpage owns the panel");
  assert(cards(reopened).length === 2, "a revalidation must not replace a subpage");

  // An in-panel mutation still reloads explicitly.
  h.gu.reloadGameUpdates(reopened);
  assert(reopened.textContent.includes("Loading"),
    "an invalidated list reloads with a visible loading state");
  await settle();
  assert(cards(reopened).length === 3, "the reload paints the mutated list");

  // A background revalidation that fails keeps whatever the user can already see.
  h.gu.renderGameUpdates(reopened);
  await settle();
  h.state.payload = { success: false, error: "backend down" };
  h.gu.revalidateGameUpdates();
  await settle();
  assert(cards(reopened).length === 3, "a failed revalidation must not empty the list");
  assert(!reopened.textContent.includes("backend down"),
    "a failed revalidation must not replace the list with an error");

  // A revalidation still in flight when the user mutates the list must not
  // resurrect the library it read before the mutation.
  const slow = harness();
  slow.state.payload = { success: true, games: [game(111)] };
  const warm = slow.newPanel();
  slow.gu.renderGameUpdates(warm);
  await settle();
  const held = slow.hold();
  const reentered = slow.newPanel();
  slow.gu.renderGameUpdates(reentered);
  slow.state.payload = { success: true, games: [game(111), game(222), game(333)] };
  slow.gu.reloadGameUpdates(reentered);
  await settle();
  assert(cards(reentered).length === 3, "the mutation repaints with authoritative data");
  held.release({ success: true, games: [game(111)] });
  await settle();
  assert(cards(reentered).length === 3,
    "a revalidation superseded by a mutation must not repaint the panel");

  // The initial load has the same generation hazard: if a mutation starts a new
  // render while the first request is pending, its late response must not paint
  // stale cards into the current panel or overwrite the rendered signature.
  const initialRace = harness();
  initialRace.state.payload = { success: true, games: [game(111)] };
  const initialPending = initialRace.hold();
  const initialPanel = initialRace.newPanel();
  initialRace.gu.renderGameUpdates(initialPanel);
  await settle();
  initialRace.state.payload = { success: true, games: [game(111), game(222)] };
  initialRace.gu.reloadGameUpdates(initialPanel);
  await settle();
  assert(cards(initialPanel).length === 2, "the post-mutation render must win immediately");
  initialPending.release({ success: true, games: [game(111)] });
  await settle();
  assert(cards(initialPanel).length === 2,
    "a late initial response must not repaint over the post-mutation list");
  const postMutationCard = cards(initialPanel)[0];
  initialRace.gu.revalidateGameUpdates();
  await settle();
  assert(cards(initialPanel)[0] === postMutationCard,
    "a late initial response must not corrupt the rendered signature");

  console.log("test_updates_cache: ok");
}

main().catch((error) => {
  console.error("FAIL:", error.message);
  process.exit(1);
});
