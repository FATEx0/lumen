// Contract checks for the Game Updates importer and simple game creator.
// Run: node tools/test_game_import_ui.js
"use strict";
const fs = require("node:fs");
const ui = fs.readFileSync("lua/menu/07-updates-tab.js", "utf8");
const helpers = fs.readFileSync("lua/menu/06-updates-helpers.js", "utf8");
const i18n = fs.readFileSync("lua/menu/02-i18n.js", "utf8");
const styles = fs.readFileSync("lua/menu/03-styles.js", "utf8");
const boot = fs.readFileSync("lua/boot.lua", "utf8");
let failures = 0;
function ok(value, message) {
  if (value) console.log("ok:  ", message);
  else { failures++; console.error("FAIL:", message); }
}

ok(/multiple\s*=\s*true/.test(ui), "file picker supports multiple files");
ok(/accept\s*=\s*["'][^"']*\.lua[^"']*\.manifest[^"']*\.zip/.test(ui),
  "file picker accepts lua, manifest and zip packages");
ok(ui.includes('call("BeginGameImport"') && ui.includes('call("UploadGameImportChunk"')
  && ui.includes('call("PrepareGameImport"') && ui.includes('call("CommitGameImport"'),
  "importer uses staged chunked backend transaction");
ok(ui.includes("renderGameCreator") && ui.includes("buildDraftLuaRequest"),
  "Add game opens a dedicated creator view");
ok(/add\.className\s*=\s*["']lumen-mbtn primary["']/.test(ui),
  "Add game uses the same primary treatment as Import games");
ok(ui.includes('call("SearchSteamGames"') && ui.includes("renderStoreResults"),
  "creator searches the Steam catalog through the local backend and lets the user choose a result");
ok(/local ALLOWLIST[\s\S]*["']SearchSteamGames["']/.test(boot),
  "Lumen formally allowlists the Steam catalog RPC");
ok(!/fetch\(["']https:\/\/store\.steampowered\.com\/api\/storesearch/.test(ui),
  "creator never calls the CORS-blocked Steam catalog directly from CEF");
ok(ui.includes("scheduleGameSearch") && /setTimeout\([^,]+,\s*280\)/.test(ui),
  "creator debounces game-name suggestions while the user types");
ok(ui.includes('role", "combobox"') && ui.includes('role", "listbox"')
  && ui.includes('role", "option"') && ui.includes("ArrowDown") && ui.includes("ArrowUp"),
  "catalog dropdown supports accessible keyboard selection");
ok(ui.includes("sourceProgressMessage") && ui.includes("bytesRead")
  && ui.includes("totalBytes"),
  "source lookup reports real transfer progress instead of a static wait state");
ok(ui.includes("steamdb.info/depot/") && ui.includes("/manifests/"),
  "creator links each valid depot to its SteamDB manifest history");
ok(ui.includes("manifestSourceHint") && ui.includes("manifestLatestHint")
  && /steamdb\.title\s*=/.test(ui),
  "SteamDB links explain ManifestID builds and identify the selected source");
ok(ui.includes("fetchAppDetails") && ui.includes("localStorage"),
  "creator resolves and locally caches game name, banner and DLC metadata");
ok(ui.includes('call("OpenExternalUrl"') && ui.includes("steamdb.info/depot/"),
  "SteamDB history opens through the existing external URL relay");
ok(ui.includes('call("SyncGamePins"') && ui.includes('call("CancelGameDraft"'),
  "creator synchronizes Latest/pinned state and finalizes its source session");
ok(/\(row\.key\s*&&\s*!\/\^\[0-9a-fA-F\]\{64\}\$\//.test(ui)
  && /hasUsableBaseKey/.test(ui) && /baseDepots/.test(ui),
  "creator accepts keyless manifest/DLC rows while requiring one usable depot key");
ok(ui.includes("virtualDepot") && ui.includes("virtualDlcNoKey"),
  "virtual DLC depots are displayed without an editable content-key requirement");
ok(/function cancelGameDraft/.test(ui)
  && /pollGameDraft[\s\S]*cancelGameDraft/.test(ui)
  && /catch\(function \(e\)[\s\S]*cancelGameDraft/.test(ui),
  "failed or timed-out source lookups cancel their private draft session");
ok(/sourceError\.code\s*=\s*state\.errorCode/.test(ui)
  && /e\s*&&\s*e\.code\s*===\s*["']not_found["']/.test(ui),
  "source lookup preserves not-found codes and gives DepotID-specific guidance");
ok(/pinsSynced/.test(ui) && /SyncGamePins/.test(ui),
  "creator trusts atomic draft commits while retaining an older-backend fallback");
ok(/addGame:\s*"Add game"/.test(i18n) && /addGame:\s*"Adicionar jogo"/.test(i18n),
  "Add game copy is localized in English and Portuguese");
ok(/importFiles:\s*"Import games"/.test(i18n) && /importFiles:\s*"Importar jogos"/.test(i18n),
  "Import games copy is localized in English and Portuguese");
ok(/appidPlaceholder:\s*"Game name or Steam AppID"/.test(i18n)
  && /appidPlaceholder:\s*"Nome do jogo ou AppID da Steam"/.test(i18n),
  "name-or-AppID search copy is localized");
ok(/sourceNotFound:\s*"No source has this game AppID\.[^\n]*DepotID\."/.test(i18n)
  && /sourceNotFound:\s*"Nenhuma fonte possui este AppID de jogo\.[^\n]*DepotID\."/.test(i18n),
  "not-found guidance distinguishes a game AppID from a DepotID");
ok(/manifestGid:\s*"ManifestID"/.test(i18n)
  && /manifestGid:\s*"ManifestID"/.test(i18n),
  "ManifestID uses the requested label");
ok(styles.includes(".lumen-game-builder") && styles.includes(".lumen-import-summary"),
  "creator and importer summary have dedicated styles");
ok(styles.includes(".lumen-builder-searchbox{position:relative")
  && styles.includes(".lumen-builder-results.open")
  && /\.lumen-builder-results\{[^}]*position:absolute/.test(styles)
  && styles.includes(".lumen-virtual-key"),
  "catalog results are an anchored dropdown and virtual DLC rows have dedicated styles");
ok(/game\.historyDepot/.test(helpers)
  && /all\[h\]\.depot\s*===\s*game\.historyDepot/.test(helpers),
  "main build history follows the backend-selected base depot");
ok(/game\.metadataAvailable[\s\S]*return null/.test(helpers),
  "known metadata never falls back to a DLC depot when no base history exists");
ok(/d\.dlcAppid/.test(ui) && /fetchAppName\(d\.dlcAppid\)/.test(ui),
  "Advanced resolves real DLC names from the associated AppID");
ok(/depotLabel\(d,\s*game\)/.test(ui) && /game\.name/.test(helpers),
  "base depot labels include the locally cached game name");
ok(/nm\.textContent\s*=\s*game\.name\s*\|\|/.test(ui),
  "game cards render the local appinfo name before the catalog lookup finishes");
ok(!/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(helpers),
  "depot labels contain no control-character separators");
ok(ui.includes("lumen-depot-id") && styles.includes(".lumen-depot-id"),
  "Advanced keeps the DepotID visible as secondary metadata");
ok(/baseContent:\s*"Game content"/.test(i18n)
  && /baseContent:\s*"Conteúdo do jogo"/.test(i18n),
  "base-content fallback labels are localized");
ok(/var _gameUpdatesCache\s*=\s*null/.test(ui)
  && /function preloadGameUpdates\(/.test(ui)
  && /if \(_gameUpdatesCache\)/.test(ui),
  "Game Updates preloads once and reuses its in-memory result across tab switches");
ok(/function invalidateGameUpdatesCache\(/.test(ui)
  && /function reloadGameUpdates\(body\)\s*\{[\s\S]*invalidateGameUpdatesCache\(\)/.test(ui),
  "explicit Game Updates mutations invalidate the preloaded result");
ok(/renderDlcSubpage\(vers\.__bodyRef,\s*game,\s*function \(\) \{\s*renderGameUpdates\(vers\.__bodyRef\);\s*\}\)/.test(ui)
  && !/renderDlcSubpage\(vers\.__bodyRef,\s*game,\s*function \(\) \{\s*reloadGameUpdates\(vers\.__bodyRef\);\s*\}\)/.test(ui),
  "Advanced back reuses the loaded Game Updates snapshot without a backend reload");
ok(/call\("DeleteAll"[\s\S]*invalidateGameUpdatesCache\(\)[\s\S]*onBack\(\)/.test(ui)
  && /call\("ClearManifests"[\s\S]*reloadGameUpdates\(guBody\)/.test(
    fs.readFileSync("lua/menu/09-overlay.js", "utf8")),
  "bulk deletion cannot leave a stale preloaded game list");

if (failures) process.exit(1);
console.log("ALL PASS");
