# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 79)

Déclencheur : ouverture de la **PR #216** (`cursor/analyse-nocturne-du-codebase-e839`) — Effects `clearActionPreview` recycle (N169), specs N152 / N170.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-a4af`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#217. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués.

HUD `refreshChatSheet` : free-list `chatFree` (**N170**). Effects `clearActionPreview` : `Parent = nil`, garder `self.actionPreview` (**N169**). Effects `clearSelection` : `Parent = nil`, garder `self.selection` (**N168**). HUD `notify` : free-list `feedFree` (**N167**). BuildingModels BuildRing : free-list `ringFree` (**N166**). Overlay Blast sphère : free-list `blastFree` (**N165**). Overlay BlastSmoke : free-list `smokeFree` (**N164**). Overlay Shockwave : free-list `shockFree` (**N163**). PointLight reste **enfant** de Blast. UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover **N152**, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). MainMenu `drawFlag` Destroy Frames encore (leftover **N171**).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #216 (passe 78) : claims vérifiés.** Effects `clearActionPreview` Parent=nil, `self.actionPreview` conservé, nil skip N154, reparent `previewTile` `self.root` si Parent nil après le skip (N169). N154 skip inter-hovers inchangé. N168 selection inchangé. **N170 livré ici.** **N152 non livré** (freeze Size=API = visual V74, interdit). Spec N170 **livrée ici**. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **PR #218** (`d46a`) V108 CapitalFlag — feel lockstep **encore**, **pas merger**. Visual **PR #217** (`ee95`) V107 flag pitch — feel `sin(time * 5)` lockstep **encore**, **pas merger**. Visual **PR #215** (`35f5`) wake `offset.X` — feel N130/N160 **déjà**, **pas merger**. Visual **PR #209** (`7188`) HUD préfixe — feel N153 **déjà**, **pas merger**. Visual **PR #211** (`8bb2`) FactoryOutput — feel **déjà**, **pas merger**. Visual **PR #212** (`2f2a`) feux navire — feel lockstep **encore**, **pas merger**.

Cette passe a **livré N170** (ce que #216 a documenté). **N152 non livré** : le seul patch distinct de l’API serait un freeze Size=API (visual V74 / `c0ec`) — interdit par la spec. Stub `Disconnect` du banc client **réparé** (sans ça, Fire accumulait les Activated au reuse).

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #216

| Claim #216 | Réalité à l’ouverture |
|---|---|
| Effects `clearActionPreview` Parent=nil (N169) | Oui. Un marqueur. `Parent = nil` si encore parenté, pas Destroy, pas `self.actionPreview = nil`. Nil skip N154. `previewTile` reparent `self.root` si Parent nil **après** le skip **avant** Color / Tween. Name `ActionPreview`. N154 skip inter-hovers inchangé. N168 selection inchangé. Check calques : snapshot `previewMarker` avant clear, `rawequal` + Parent nil + re-preview `effects.root`. `refreshChatSheet` Destroy encore au moment de l’ouverture. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| Specs N152 / N170 | **N170 livré ici.** N152 **laissé ouvert** (pulse Z conservé ; freeze Size=API = visual V74, ne pas merger `c0ec`). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #216, visuelles #39/…/`d46a` V108 CapitalFlag / `ee95` V107 flag / `35f5` V106 wake / `7188` V103 **fermé** / `8bb2` V104 FactoryOutput / `2f2a` V105 feux / `6c83` V102 compact. **#216 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `d46a` / `ee95` / `35f5` / `7188` / `8bb2` / `2f2a` / `6c83` / `fce3` / `b7e3` / `adfc` ni hardening `41e2` / `93f6` / `e291` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N170 est cosmétique HUD (catalogue QuickChat). Risques documentés, non corrigés ici (hors N170) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip `rng > 0.12` seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N170. Overlay `explosion` n’a plus de `Destroy` (Blast / Shockwave / BlastSmoke tous poolés). BuildingModels `playConstruction` BuildRing **poolé**. HUD `notify` TextLabel **poolé**. Effects `clearSelection` **poolé**. Effects `clearActionPreview` **poolé**. HUD `refreshChatSheet` TextButton **poolé**. UnitModels flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze Size=API). MainMenu `drawFlag` Destroy encore (leftover N171).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N170 du rapport #216. N152 **non livré** (spec : si le seul patch est un freeze, ne pas livrer).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| HUD `refreshChatSheet` Destroy+`Instance.new` chaque onglet / cible / Retour (N170) | `HUD.luau` (`parkChatButtons` / `takeChatButton` / `bindChatActivated`, UIGridLayout une fois dans `buildChatSheet`, `Parent = nil` + `chatFree`, Disconnect Activated, Parent `self.chatBody`), `tests/guistubs.luau` (`Disconnect` retire le handler — sinon Fire double-fire au reuse), `tests/client.luau` (check messages rapides leftover N170 : snapshot TextButton social **avant** autre onglet, retour social, `rawequal` Parent `hud.chatBody`, un seul `UIGridLayout`, asserts envoi **gardés**) | Leftover N169. Catalogue vs pending. Pas de tableau partagé avec `feedFree`. `Parent = nil` si TextButton, pas Destroy, pas de second UIGridLayout. **Disconnect Activated obligatoire** sinon double envoi QuickChat. Parent = **`self.chatBody`** (pas `hud.feed`, pas `overlay.root`, pas `effects.root`). Cosmétique. Flame leftover N152 **alors**. MainMenu `drawFlag` leftover N171 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), MainMenu `drawFlag` Destroy (**N171**), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, PlacementPreview Size rayon (visual V76, feel Size = API), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline** **et** N160 free-list, **pas merger**), tribus `humanTargetProtected`. Overlay / BuildingModels / Effects / UnitModels / WorldCamera / WorldRenderer / serveur **non édités**. Flame **non**. Blast **non**. BlastSmoke **non**. Shockwave **non**. DeliveryPulse **non**. `routePart` **non**. Dismiss `table.remove(index)` **non**. HUD `feedFree` **inchangé**. Destroy du modèle navire **inchangé**. `previewTile` N154 skip **inchangé**. `clearSelection` N168 **inchangé**. `clearActionPreview` N169 **inchangé**. Dismiss delay Destroy **inchangé**.

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (seq obligatoire en playing, apply immédiat) → tick :
  Bots.step → Navy.step (syncCarriers si dirty, spawn via navalBasesBySlot ;
    stepCarriers via carrierBuf/targetBuf, early-out 0 carrier / 0 autre slot ;
    coule TRADE si PORT absent ; TRANSPORT retraite si owner ~= targetSlot ;
    spawnTradeShips si tick % 45 == 0, via portsByTile ;
    findSeaPath via pathWalkBuf, retour unique) → Nukes.step
              (stepCooldowns SAM+silo indexés ; tryIntercept via samsBySlot ;
               launch via silosBySlot) → Trade.step (factoriesBySlot + factoryBuf)
              → Diplomacy.step (expiredBuf N79) → GameState.step → replicate(
                flushOwnerDelta via dirtyIndexBuf,
                playerStatsForReplicate + pricesFor + Research.progress (min courant),
                fireDeployed, snapshotBoats, snapshotMissiles,
                flushBuildingDelta via buildingSnapBuf)
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn/doom,
    cancelOpposingFronts via doomedBuf, collapsingBuf 10 Hz,
    stepDoomsday via stripBuf, stripTerritory table.clear), BoatFront
    (park isBeachhead via parkedBuf), AimFront,
    tribus, spawn bots différé 15 s
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas le corps de `GameState.stepAttacks`.
- **Vérité d’équilibrage** = `ChantierB.apply(Config)` après `install()`, pas `Config.luau` seul.
- **Beachhead vivant** = `BoatFront.seedBeachhead` : frontier = voisins encore à la cible, flag `isBeachhead`. Stub = `error(...)`. Deux débarquements du même couple = **deux** tas (N5 ouvert). Wrap `launchAttack` gare via `parkedBuf` (**N87**).
- **`areAllied`** = deux directions **et** `tick < expiry` (`true` legacy tests reste vivant).
- **Réplication :** StateDelta / UnitSnapshot / BuildingDelta / plunder / trade / explosions / notify&sfx / Diplomacy.viewFor 1 Hz. Playing 10 Hz ; lobby vide et ended → 1 Hz.
- HUD `refreshChatSheet` poolé (**N170**, `chatFree`). Effects `clearActionPreview` poolé (**N169**, un marqueur). Effects `clearSelection` poolé (**N168**, un marqueur). HUD `notify` free-list (**N167**). BuildingModels BuildRing free-list (**N166**). Overlay Blast sphère free-list (**N165**). Overlay BlastSmoke free-list (**N164**). Overlay Shockwave free-list (**N163**). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). MainMenu `drawFlag` Destroy encore (**N171**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N171)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153–N170** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N171** = nouveau. **N170** fermé ici.

Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover feel MainMenu `drawFlag` Destroy+`Instance.new` = **N171** (N170 `chatFree` **déjà**, N167 `feedFree` **déjà**, Theme.corner parent **conservé**, **≠** visual, **≠** `drawTerrainPreview`). Visual V108 CapitalFlag **ouverte** sur `d46a` / PR #218 (feel lockstep — ne pas merger). Visual V107 flag pitch **ouverte** sur `ee95` / PR #217 (feel lockstep `sin(time * 5)` — ne pas merger). Visual V106 wake **ouverte** sur `35f5` / PR #215 (feel N130/N160 **déjà** — ne pas merger). Visual V103 HUD préfixe **fermée** sur `7188` / PR #209 (feel N153 **déjà**, ne pas merger). Visual V104 FactoryOutput **ouverte** sur `8bb2` / PR #211 (feel **déjà** — ne pas merger). Visual V105 feux navire **ouverte** sur `2f2a` / PR #212 (feel lockstep — ne pas merger). Visual V102 compact préfixe **fermée** sur `6c83` (feel N114 **déjà**). Visual V101 `dirtyHead` **fermée** sur `fce3` (feel N112 **déjà**).

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153–N170 (pools Overlay/Effects/BuildingModels/HUD/selection/preview/chat **déjà**). Distinct de N151 (trail Transparency), de N163–N170 (pools Overlay explosion / BuildRing / HUD feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet`), de N171 (`drawFlag`), de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**. Ne pas toucher trail. Ne pas toucher `BuildingModels`. Ne pas toucher Overlay. Ne pas toucher HUD. Ne pas toucher Effects. Ne pas toucher MainMenu.

**Problème :** N170 ferme le pool `refreshChatSheet`. N171 reste ouvert (`drawFlag`). N151 ferme le trail. N153–N169 ferment HUD préfixe / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed / `clearSelection` / `clearActionPreview`. Reste, **chaque frame** (`UnitModels.place`, 60 Hz, une Part `EngineFlame` par ogive) :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (plus de pulse Size, `c0ec` / PR #151). Feel **garde** le pulse Z. Ne pas porter `c0ec`. Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**. Role `"flame"` **inchangé**. Shape `Ball` **inchangé**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. HUD chat **déjà** N170 — ne pas y revenir. `clearActionPreview` **déjà** N169. Blast **déjà** N165. Visual V74 freeze **interdit** (feel ≠ visual). **Passes 61–79 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse `1.8 + math.sin(time * 18) * 0.45`. **Ne pas** geler Size (visual V74 Option A, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)`. XY `0.62` / base `1.8` / freq `18` / amp `0.45` **inchangés**.

2. **Garder le pulse.** Ne **pas** poser Size = API. Ne **pas** « fermer » trail / HUD / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` (N151–N170 déjà). Ne **pas** lire `piece.part.Size` (alloc). Ne pas porter visual. Après N170. `BuildingModels` **non**. Overlay **non**. HUD **non**. Effects **non**. MainMenu **non**. `createMissile` construction **non** (taille initiale `Vector3.new(0.62, 0.62, 2.3)` inchangée).

3. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N171 seulement.** N152 reste alors ouvert (feel-diverged vs V74). Ne pas inventer un cache Size. Ne pas skip-si-inchangé (N2, pas ici).

4. Tests « navires, missiles et interpolation » leftover N151 trail **et** leftover N148 mesh **et** leftover N147 Fin **doivent rester verts**. Tests « messages rapides » leftover N170 `chatFree` reuse **doivent rester verts**. Tests « calques d'entites, effets et apercu » leftover N169 `clearActionPreview` reuse **et** leftover N168 `clearSelection` reuse **et** leftover N155 `rawequal` 2000→2001 **doivent rester verts**. Tests « vagues de conquete » leftover N167 `feedFree` reuse **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` flame **seulement**, **un** `elseif`) **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N152. Overlay **non**. **Ne pas** éditer le serveur. **Ne pas** toucher Shockwave ni BlastSmoke ni Blast sphère ni BuildRing ni HUD feed ni `clearSelection` ni `clearActionPreview` ni `refreshChatSheet` ni `drawFlag`.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ N151 (trail Z) ≠ visual V74 (freeze Size=API, ne pas merger) ≠ N163 (Shockwave pool) ≠ N164 (BlastSmoke pool) ≠ N165 (Blast sphère pool) ≠ N166 (BuildRing pool) ≠ N167 (HUD feed pool) ≠ N168 (`clearSelection`) ≠ N169 (`clearActionPreview`) ≠ N170 (`refreshChatSheet` déjà) ≠ N171 (`drawFlag`) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N171 dans le même worker. Pulse Z **conservé** — ne pas figer à 1.8. Un `elseif` flame.

---

### ISSUE-N171 — MainMenu `drawFlag` Destroy+`Instance.new` (feel)

**Priorité :** P3 alloc client MainMenu. Leftover explicite après N170 (`refreshChatSheet` déjà). Distinct de N152 (UnitModels Size), de N170 (`chatFree` catalogue **déjà**), de N167 (`feedFree` notify **déjà**), de `drawTerrainPreview` (Destroy Frames miniature — leftover **N172**, **ne pas** fermer ici), de visual V107 (UnitModels flag pitch — **ne pas merger** `ee95`). `MainMenu.drawFlag` **seulement**. Ne pas toucher HUD (N170 **déjà**). Ne pas toucher `drawTerrainPreview`. Ne pas toucher Overlay. Ne pas toucher UnitModels. Ne pas toucher Effects.

**Problème :** N170 ferme le pool `refreshChatSheet`. N152 reste ouvert (freeze interdit). Reste, **chaque sélection de nation** (`MainMenu.drawFlag`, 4 call sites : `playerFlag`, `identityFlag`, grille nations `flagCell`, re-select) :

```
for _, child in parent:GetChildren() do
    if child:IsA("Frame") then
        child:Destroy()
    end
end
local function band(...)
    local f = Instance.new("Frame")
    -- Position / Size / BackgroundColor3 / Rotation / Parent = parent
end
```

2–4 bandes Destroy+new par drapeau, × 16 nations au parcours grille, × 2 pastilles identité/joueur. Distinct de leftover N152 (`Size = Vector3.new` flamme). Distinct de leftover N170 (`chatFree` **déjà** — **ne pas** partager). Distinct de leftover N167 (`feedFree` **déjà**). Motifs `vertical` / `horizontal` / `cross` / `diagonal` / `quarters` **inchangés**. Couleurs `flag.colors` **inchangées**. `ClipsDescendants` du parent **inchangé**.

**Piège UICorner :** `Theme.corner` vit sur le **parent** (pastille / cellule), pas sur les bandes. Le Destroy actuel saute déjà le UICorner (`IsA("Frame")` seulement). **Garder** ce filtre. Un pool qui Destroy le UICorner = coins carrés, test « selection de chaque nation » peut rester vert (pas d’assert visuel) mais le lobby est cassé. **Ne pas** recréer `Theme.corner` au reuse des bandes (elles n’en ont pas).

**Piège parents multiples :** `drawFlag` n’est **pas** une méthode d’instance — `MainMenu.drawFlag(parent, flag)`. Quatre parents distincts (`self.playerFlag`, `self.identityFlag`, `flagCell` grille, éventuellement un autre). Free-list **module** `flagFree` (ou `self.flagFree` si on hisse un champ) : pop + `Parent = parent` argument. Un bandeau resté parenté à l’ancienne cellule = drapeau fantôme / test nation faux.

**Piège Rotation :** motif `diagonal` pose `Rotation = -30`. Au reuse depuis un `vertical` (Rotation 0) **reset** `Rotation = rotation or 0`. Oubli = bandes de travers.

**Pourquoi 20K CCU :** leftover N170. 8 clients × cycle nations lobby × Destroy+new de N Frames. Pas d’autorité (cosmétique menu). `chatFree` **déjà** N170 — ne pas y revenir. Visual V107 flag pitch **interdit** (ne pas merger `ee95`). **Oubli de garder UICorner parent** = coins cassés. **Si le seul patch est un merger V107 : ne pas livrer.**

**Worker :**

1. Dans `MainMenu.drawFlag` seulement : **ne plus** `Destroy` les Frame bandes. `Parent = nil` + push `flagFree` (nommer **`flagFree`**, pas `chatFree` / `feedFree` / `previewFree`). Pop O(1) depuis la fin. Si vide : `Instance.new("Frame")` comme `band()` aujourd’hui. Au reuse : reset `BackgroundColor3` / `Position` / `Size` / `Rotation` / `BorderSizePixel = 0`. `Parent = parent` (l’argument, **pas** `hud.chatBody`, **pas** `hud.feed`, **pas** `overlay.root`). **Sauter** UICorner / UIStroke / TextLabel dans la boucle (comme aujourd’hui `IsA("Frame")`). Motifs **inchangés**.

2. **Garder les bandes.** Ne **pas** recréer après `selectNation` si `flagFree` a un exemplaire. Ne **pas** poser un Name obligatoire. Ne **pas** toucher N170 `chatFree`. Ne **pas** toucher `drawTerrainPreview`. Ne **pas** toucher Theme.corner du parent. Après N170. Flame **non** (N152). Overlay **non**. HUD **non**. Effects **non**. `BuildingModels` **non**. Parent = **argument `parent`** obligatoire au reuse.

3. Tests « selection de chaque nation et de chaque mode » **doivent rester verts**. **Ajouter** (dans ce check) : snapshot une Frame bande d’un `playerFlag` ou `identityFlag` **avant** `selectNation` d’une autre nation, après select, `rawequal` de la Frame réparentée **ou** `#flagFree` cohérent — au choix, mais **pas** d’assert Name. Tests « messages rapides » leftover N170 **doivent rester verts**. Tests « calques d'entites, effets et apercu » leftover N169 / N168 / N155 **doivent rester verts**. Tests « vagues de conquete » leftover N167 `feedFree` reuse **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client `selection de chaque nation` **doit rester vert**. **Ne pas** `testFlushDelays`. Check messages rapides leftover N170. Check calques leftover N169 / N168. Check vagues leftover N167. Check navires leftover N152 flame. **Ne pas** casser N170 (`chatFree` snapshot + reuse `rawequal` Parent `hud.chatBody`, un `UIGridLayout`). **Ne pas** casser N169 (`self.actionPreview` conservé). **Ne pas** casser N168 (`self.selection` conservé). **Ne pas** casser N167 (`feedFree`). Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `MainMenu.luau` (`drawFlag` **seulement**, helper reuse à côté de `band()`). `tests/client.luau` **seulement** le check selection nation (commentaire leftover N171, **ajouter** snapshot + reuse si possible, **garder** la boucle Nations/GameModes). `HUD.luau` **non**. `Effects.luau` **non**. `Overlay.luau` **non**. `UnitModels.luau` **non**. `drawTerrainPreview` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher flame ni Blast ni HUD chat ni feed ni `clearSelection` ni `clearActionPreview`. **Ne pas** merger visual V107.

**Contraintes :** pas de RemoteFunction. **N171 feel ≠ N170 (`refreshChatSheet` déjà) ≠ N167 (HUD feed pool déjà) ≠ N152 (flame Size, ne pas freeze V74) ≠ visual V107 (flag pitch, ne pas merger `ee95`) ≠ N172 (`drawTerrainPreview`, ne pas fermer ici) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N152 dans le même worker. Free-list **`flagFree`** — **pas** `chatFree`. **Pas Destroy** des Frame bandes. **Pas de UICorner sur les bandes.** **Reset Rotation.** Distinct `chatFree` / `feedFree` / `flashFree` — **ne pas** partager. Parent argument **obligatoire**. HUD N170 **obligatoire** inchangé. `drawTerrainPreview` Destroy **obligatoire** inchangé.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; HUD feed → **N167 fait** ; `clearSelection` → **N168 fait** ; `clearActionPreview` → **N169 fait** ; `refreshChatSheet` → **N170 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (… ; HUD feed pool → **N167** ; `clearSelection` → **N168** ; `clearActionPreview` → **N169** ; `refreshChatSheet` → **N170** ; Overlay explosion + chantier + fil clos ; `drawFlag` = **N171**) |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | ouvert |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 factions) | P1 | ouvert |
| N13 | Parité combat (ère / cost factor / constantes mortes) | P2 | ouvert |
| N14 | Apply immédiat vs lockstep (feel #19) | P1 | ouvert (produit) |
| N15 | `PREPARATION_DURATION=0` vs gardes `combatUnlocked` | P2 | ouvert |
| N16 | Buffer `defense` vs scan bunkers + `findSeaPath` 40k | P2 | **N37+N42+N45 faits** ; path résultat → **N83 fait** |
| N17 | Humains éliminés occupent le cap | P2 | ouvert |
| N18 | Heap AimFront ≠ ChantierB / BoatFront | P2 | ouvert (frontier mixte mag vs TERRAIN_COST) |
| N19 | Embargo allié + tribus auto-accept | P2 | ouvert ; **tribus n’appellent pas `humanTargetProtected`** (écart feel vs hardening/visual — ne pas porter sans spec dédiée) |
| N20 | `railIncome` vs `deliveryValue` | P2 | **fait** `stopBonus` ; reste niveau live vs snapshot colis |
| N21–N24, N26, N29–N32 | (fermés passes 5–10) | — | **faits** |
| N25 | `MAX_BOATS_PER_PLAYER` 6 vs 3 | P3 | ouvert |
| N27 | Embargo land trade | P2 | **doc** maritime-only |
| N28 | `RequestSnapshot` mort client | P2 | ouvert (serveur rate-limite ; client n’envoie jamais) |
| N33 | `BOAT_LANDING_BONUS` mort | P2 | ouvert |
| N34–N151, N153–N170 | (voir rapport #216) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–79) |
| N171 | MainMenu `drawFlag` Destroy+`Instance.new` | P3 | **nouveau** (`flagFree`, garder UICorner parent, Reset Rotation, Parent argument, N170 chat **déjà**, `drawTerrainPreview` Destroy **conservé**, **≠** visual V107) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 / #167 / #169 / #171 / #173 / #176 / #178 / #181 / #183 / #185 / #187 / #189 / #191 / #193 / #195 / #197 / #200 / #202 / #204 / #206 / #208 / #210 / #213 / #214 / #216 `NIGHTLY_REPORT.md` historique.

---

## 6. Drift Config → `ChantierB.apply` (extrait)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | formule custom |
| `MAX_TILES_PER_TICK` | 400 | 56 | **non** (`guard<80`) |
| `DEFENSE_RADIUS` | 6 | 30 | index bunkers (N42), plus d’écritures buffer (N45) |
| `BOAT_TROOP_RATIO` | 0.2 | 0.2 | oui |
| `RETREAT_LOSS` | 0.25 | 0.25 | oui |
| `SAM_INTERCEPT_CHANCE` | **1.0** | 1.0 | oui (N26 clos) |
| `SAM_RANGE` | 34 | 70 | oui |
| `SAM_COOLDOWN` | 90 | 75 | oui |
| `SILO_COOLDOWN` | 90 | **90** (apply ne le touche pas) | oui (`Nukes.launch` + `stepCooldowns`) |
| `TRUCK_GOLD_BASE` | 10 | 14 | oui |
| `TRAIN_STOP_BONUS` | **0.12** | 0.12 | Trade + HUD (N20) |
| `BOAT_LANDING_BONUS` | 1.35 | 1.35 | **non** (N33) |
| `MAX_BOATS_PER_PLAYER` | 6 | 6 | oui (N25) |
| `PREPARATION_DURATION` | 0 | 0 | forcé true |
| `ALLIANCE_DURATION` | 3000 | 3000 | oui (`areAllied` + `Diplomacy.step`) |
| `ALLOW_UNSEQUENCED_INTENTS` | **false** | n/a | oui (N41) |
| `TRADE_SHIP_INTERVAL` | 45 | n/a | oui (N63, pas 10 Hz) |
| `MAX_TRADE_SHIPS` | 24 | n/a | oui (early-out N63) |
| `WARSHIP_SHELL_RATE` | 20 | 20 | oui (N67) |
| `RAIL_RANGE` | 56 | n/a | oui (N84) |
| `COLLAPSE_MIN_TILES` | 100 | 100 | oui (N86 wrap, N88 scan) |
| `SPAWN_RADIUS` | 3 | n/a | oui (N93 banc `keep=8`, N94 strip, N55 isolation) |
| `CHUNK_REBUILDS_PER_FRAME` | 3 | n/a | oui (N102/N104/N106/N112/N114 compact seuil 32) |
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N170 `refreshChatSheet` pool) |

---

## 7. Preuve tests

`./tests/run.sh` → **exit 0**.

Serveur :

```
seed 7 / 99991 / 31337 / 1234567 : 18 factions, invariants OK
factions : 18
intentions : sequence, idempotence, apply immediat, rate limit OK
stripBuf : rot sous quota, deux camps, tiles vs buffer (N93)
stripTerritory : table.clear in-place, voisin intact (N94)
allyBuf : bot sans pacte, next nil (N91)
validTiles : deux resolve CITY, tile identique (N90)
destroyBuf : leftover A→B, CITY B survit (N89)
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.72
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `fil de notifications sature` leftover N153 / leftover N167 commentaire **sans** flush ; `messages rapides` leftover N170 `chatFree` snapshot + reuse Parent `hud.chatBody` + un `UIGridLayout` + envoi `social_gg` / `attack_target` slot 3 ; `calques d'entites, effets et apercu` leftover N155 reuse / leftover N168 `clearSelection` Parent nil + reselect `effects.root` / leftover N169 `clearActionPreview` Parent nil + re-preview `effects.root` ; `hover spawn isolation` leftover N58 ; `construction du monde 3D` leftover N137/N138 ; `pose et capture de chaque type de batiment` leftover N136 / leftover N132 / leftover N162 commentaire **sans** flush / leftover N166 commentaire **sans** flush / leftover N167 commentaire ; `modeles procéduraux` leftover N150/N149 ; `apercu de placement pour chaque batiment` leftover N129 ; `livraison : le gain s'affiche sur la gare` leftover N159 **sans** flush ; `navires, missiles et interpolation` leftover N151 trail / leftover N152 flame Size / leftover N148 mesh / leftover N160 wake **sans** flush / leftover N161 splash **sans** flush / leftover N163 Shockwave **sans** flush / leftover N164 BlastSmoke **sans** flush / leftover N165 Blast **sans** flush, skip retraite id=1 N56 ; `vagues de conquete` N167 `feedFree` reuse (`testFlushDelays` → `#feedFree >= 1` **avant** N160, `hud:notify` texte nouveau `rawequal` Parent `hud.feed`, Dismiss recréé, `# == feedN - 1`) / leftover N166 `BuildRing` reuse / leftover N165 `Blast` reuse / leftover N164 `BlastSmoke` reuse / leftover N163 `Shockwave` reuse / leftover N162 `DeliveryPulse` reuse / leftover N161 `LandingSplash` reuse / leftover N160 `LaunchWake` reuse / leftover N159 `goldPopup` reuse / leftover N158 `floatingText` reuse / leftover N157 `conquestPulse` reuse / leftover N156 `tileFlash` reuse. Serveur **non** touché cette passe. `UnitModels.luau` **non** touché. `WorldCamera.luau` **non** touché. Overlay **non** touché. BuildingModels **non** touché. Effects **non** touché. Pulse flamme Size **inchangé** (N152). `drawFlag` Destroy **inchangé** (N171). HUD `refreshChatSheet` **poolé**. Stub `Disconnect` **répare** le double-fire.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass79.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N170 est un recycle TextButton HUD vérifié par le banc headless (`messages rapides` snapshot + reuse Parent `chatBody` + un UIGridLayout + envoi sans double-fire). Pulse flamme Size **inchangé** (N152). `drawFlag` Destroy **inchangé** (N171).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N170 n’ajoute **pas** de require (référence locale HUD `chatFree`). N152 restera dans `UnitModels.place` flame. N171 restera dans `MainMenu.drawFlag`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Distinct trail N151. Distinct Overlay N163–N165 **déjà**. Distinct BuildRing N166 **déjà**. Distinct HUD N167 **déjà**. Distinct `clearSelection` N168 **déjà**. Distinct `clearActionPreview` N169 **déjà**. Distinct `refreshChatSheet` N170 **déjà**. Distinct MainMenu leftover N171. Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N170 : `HUD.refreshChatSheet` seulement. **Pas** Destroy des TextButton. Free-list `chatFree` (pas `feedFree`). **Garder** le `UIGridLayout` (ne pas en recréer un). **Disconnect** `Activated` avant rebranchement (oubli = double-fire, test « messages rapides » rouge). Parent `self.chatBody`. Ne **pas** `Theme.corner` / `Theme.stroke` au reuse. MouseEnter/Leave **conservés**. Dismiss delay Destroy **conservé**. Distinct N167 `feedFree`. Distinct N169 preview. Distinct visual V103 (ne pas merger `7188`). **Ne pas** flush. **Ne pas** casser N169 ni N168 ni N167 ni N154. Catalogue vs pending **inchangé**. Stub banc : `Disconnect` **doit** retirer le handler (no-op = Fire accumule).

Piège N171 (à venir) : `MainMenu.drawFlag` seulement. **Pas** Destroy des Frame bandes. Free-list `flagFree` (pas `chatFree`). **Garder** le UICorner du parent (filtre `IsA("Frame")`). **Reset Rotation** (diagonal `-30` vs vertical `0`). Parent = argument `parent` (quatre call sites). Ne **pas** toucher `drawTerrainPreview`. Distinct N170 `chatFree`. Distinct visual V107 (ne pas merger `ee95`). **Ne pas** flush. **Ne pas** casser N170 ni N169 ni N168 ni N167. Motifs **inchangés**.
