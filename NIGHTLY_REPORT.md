# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 82)

Déclencheur : ouverture de la **PR #223** (`cursor/analyse-nocturne-du-codebase-260d`) — MainMenu `drawTerrainPreview` recycle (N172), specs N152 / N173.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-8845`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#223. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués.

VictoryScreen `show` `Value` : free-list `valueFree` (**N173**). MainMenu `drawTerrainPreview` : free-list `previewFree` (**N172**). MainMenu `drawFlag` : free-list `flagFree` (**N171**). HUD `refreshChatSheet` : free-list `chatFree` (**N170**). Effects `clearActionPreview` : `Parent = nil`, garder `self.actionPreview` (**N169**). Effects `clearSelection` : `Parent = nil`, garder `self.selection` (**N168**). HUD `notify` : free-list `feedFree` (**N167**). BuildingModels BuildRing : free-list `ringFree` (**N166**). Overlay Blast sphère : free-list `blastFree` (**N165**). Overlay BlastSmoke : free-list `smokeFree` (**N164**). Overlay Shockwave : free-list `shockFree` (**N163**). PointLight reste **enfant** de Blast. UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover **N152**, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). HUD `notify` delay `Dismiss` Destroy encore (leftover **N174**).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #223 (passe 81) : claims vérifiés.** MainMenu `drawTerrainPreview` Parent=nil, `previewFree`, filtre `IsA("Frame")` sur `frame` seulement, Reset Size/ZIndex, shade frère, océan non dessiné, Parent argument (N172). `drawFlag` N171 déjà. N152 non livré (freeze Size=API = visual V74, interdit). Stub `Disconnect` inchangé. **N173 livré ici.** Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **branche `9922`** V111 flame `frame.X` — feel `sin(time * 18)` **sans** phase spatiale **encore**, **pas merger** (N152 freeze **toujours** interdit). Visual **PR #222** (`9726`) V110 PortCraneCable — feel lockstep `sin(time * 0.8)` **encore**, **pas merger**. Visual **PR #220** (`c6b5`) V109 PortCraneBoom — feel lockstep **encore**, **pas merger**. Visual **PR #218** (`d46a`) V108 CapitalFlag — feel lockstep **encore**, **pas merger**. Visual **PR #217** (`ee95`) V107 flag pitch — feel `sin(time * 5)` lockstep **encore**, **pas merger**. Visual **PR #215** (`35f5`) wake `offset.X` — feel N130/N160 **déjà**, **pas merger**. Visual **PR #209** (`7188`) HUD préfixe — feel N153 **déjà**, **pas merger**. Visual **PR #211** (`8bb2`) FactoryOutput — feel **déjà**, **pas merger**. Visual **PR #212** (`2f2a`) feux navire — feel lockstep **encore**, **pas merger**.

Cette passe a **livré N173** (ce que #223 a documenté). **N152 non livré** : le seul patch distinct de l’API serait un freeze Size=API (visual V74 / `c0ec`) — interdit par la spec.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #223

| Claim #223 | Réalité à l’ouverture |
|---|---|
| MainMenu `drawTerrainPreview` Parent=nil (N172) | Oui. Frame tuiles. `Parent = nil` + `previewFree`, pas Destroy. Filtre `IsA("Frame")` sur `frame` seulement (shade frère + UIGradient intact). Reset Size/ZIndex/BackgroundColor3/Position/BackgroundTransparency/BorderSizePixel. Parent argument (`featuredPreview` 32×20 / cartes mode 24×12). Océan non dessiné. Check selection : snapshot + reuse `rawequal` Parent `featuredPreview` **ou** `#previewFree`. `drawFlag` N171 déjà. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| Specs N152 / N173 | **N173 livré ici.** N152 **laissé ouvert** (pulse Z conservé ; freeze Size=API = visual V74, ne pas merger `c0ec`). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #223, visuelles #39/…/`9726` V110 PortCraneCable / `c6b5` V109 PortCraneBoom / `d46a` V108 CapitalFlag / `ee95` V107 flag / `35f5` V106 wake / `7188` V103 **fermé** / `8bb2` V104 FactoryOutput / `2f2a` V105 feux / `6c83` V102 compact. **#223 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `9922` / `9726` / `c6b5` / `d46a` / `ee95` / `35f5` / `7188` / `8bb2` / `2f2a` / `6c83` / `fce3` / `b7e3` / `adfc` ni hardening `41e2` / `93f6` / `e291` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N173 est cosmétique écran de fin. Risques documentés, non corrigés ici (hors N173) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip `rng > 0.12` seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N173. Overlay `explosion` n’a plus de `Destroy` (Blast / Shockwave / BlastSmoke tous poolés). BuildingModels `playConstruction` BuildRing **poolé**. HUD `notify` TextLabel **poolé**. Effects `clearSelection` **poolé**. Effects `clearActionPreview` **poolé**. HUD `refreshChatSheet` TextButton **poolé**. MainMenu `drawFlag` Frame **poolé**. MainMenu `drawTerrainPreview` Frame **poolé**. VictoryScreen `Value` **poolé**. UnitModels flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze Size=API). HUD `Dismiss` delay Destroy encore (leftover N174).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N173 du rapport #223. N152 **non livré** (spec : si le seul patch est un freeze, ne pas livrer).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| VictoryScreen `show` Destroy+`Theme.label` `Value` chaque `show` / relance (N173) | `VictoryScreen.luau` (`parkValue` / `takeValue`, `Parent = nil` + `valueFree`, Name `Value` conservé, Reset `Text`/`TextColor3`/`TextSize`/`FontFace`/`BackgroundTransparency`/`AnchorPoint`/`Position`/`Size`/`TextXAlignment`/`ZIndex`, Parent `row`, ligne vide parque), `tests/client.luau` (check ecran leftover N173 : snapshot TextLabel `Value` de `victory.rows[1]` **après** le premier `show` **avant** `hide`, après le second `show`, `rawequal` Parent row **ou** `#valueFree`) | Leftover N172. Podium 5 scores Destroy+new × relance. Pas de tableau partagé avec `previewFree` / `flagFree` / `chatFree` / `feedFree`. `Parent = nil` si TextLabel, pas Destroy, pas de Theme.corner. **Reset TextXAlignment obligatoire** sinon scores collés à gauche. **Name=Value obligatoire** sinon empilement. Parent = **`row`**. Early-out Visible **conservé**. Cosmétique. Flame leftover N152 **alors**. HUD `Dismiss` leftover N174 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), HUD `Dismiss` delay Destroy (**N174**), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, PlacementPreview Size rayon (visual V76, feel Size = API), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline** **et** N160 free-list, **pas merger**), tribus `humanTargetProtected`. Overlay / BuildingModels / Effects / UnitModels / WorldCamera / WorldRenderer / HUD / MainMenu / serveur **non édités**. Flame **non**. Blast **non**. BlastSmoke **non**. Shockwave **non**. DeliveryPulse **non**. `routePart` **non**. Dismiss `table.remove(index)` **non**. HUD `chatFree` **inchangé**. HUD `feedFree` **inchangé**. Destroy du modèle navire **inchangé**. `previewTile` N154 skip **inchangé**. `clearSelection` N168 **inchangé**. `clearActionPreview` N169 **inchangé**. `refreshChatSheet` N170 **inchangé**. Dismiss delay Destroy **inchangé**. `drawFlag` N171 **inchangé**. `drawTerrainPreview` N172 **inchangé**.

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
- VictoryScreen `show` `Value` poolé (**N173**, `valueFree`). MainMenu `drawTerrainPreview` poolé (**N172**, `previewFree`). MainMenu `drawFlag` poolé (**N171**, `flagFree`). HUD `refreshChatSheet` poolé (**N170**, `chatFree`). Effects `clearActionPreview` poolé (**N169**, un marqueur). Effects `clearSelection` poolé (**N168**, un marqueur). HUD `notify` free-list (**N167**). BuildingModels BuildRing free-list (**N166**). Overlay Blast sphère free-list (**N165**). Overlay BlastSmoke free-list (**N164**). Overlay Shockwave free-list (**N163**). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). HUD `Dismiss` delay Destroy encore (**N174**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N174)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153–N173** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N174** = nouveau. **N173** fermé ici.

Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover feel HUD `notify` delay Destroy `Dismiss` = **N174** (N173 `valueFree` **déjà**, N172 `previewFree` **déjà**, N171 `flagFree` **déjà**, N170 `chatFree` **déjà**, N167 `feedFree` **déjà**, Name `Dismiss` **conservé**, **≠** visual, **≠** `Value`). Visual V110 PortCraneCable **fermée** sur `9726` / PR #222 (feel lockstep `sin(time * 0.8)` **encore** — ne pas merger). Visual V111 flame `frame.X` **fermée** sur `9922` (feel `sin(time * 18)` **sans** phase — ne pas merger, **≠** N152 freeze). Visual V109 PortCraneBoom **fermée** sur `c6b5` / PR #220 (feel lockstep — ne pas merger). Visual leftover V1 packing spawn / V7 anti-splash / V9b Persistence / V13 rot doomsday / V14b flushOwnerDelta en-tête. Ne pas merger visual `9922` / `9726` / `c6b5` / `d46a`.

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153–N173 (pools Overlay/Effects/BuildingModels/HUD/selection/preview/chat/drapeau/miniature/podium **déjà**). Distinct de N151 (trail Transparency), de N163–N173 (pools Overlay explosion / BuildRing / HUD feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` / `drawFlag` / `drawTerrainPreview` / `Value`), de N174 (`Dismiss` delay), de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**. Ne pas toucher trail. Ne pas toucher `BuildingModels`. Ne pas toucher Overlay. Ne pas toucher HUD. Ne pas toucher Effects. Ne pas toucher MainMenu. Ne pas toucher VictoryScreen.

**Problème :** N173 ferme le pool `Value`. N174 reste ouvert (`Dismiss` delay Destroy). N151 ferme le trail. N153–N172 ferment HUD préfixe / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` / `drawFlag` / `drawTerrainPreview`. Reste, **chaque frame** (`UnitModels.place`, 60 Hz, une Part `EngineFlame` par ogive) :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (plus de pulse Size, `c0ec` / PR #151). Visual V111 (`9922`) a ajouté `frame.X * 0.1` dans le sin — **ne pas porter**. Feel **garde** le pulse Z `sin(time * 18)` **sans** phase spatiale. Ne pas porter `c0ec` ni `9922`. Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**. Role `"flame"` **inchangé**. Shape `Ball` **inchangé**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. HUD chat **déjà** N170 — ne pas y revenir. `drawFlag` **déjà** N171. `drawTerrainPreview` **déjà** N172. `Value` **déjà** N173. `clearActionPreview` **déjà** N169. Blast **déjà** N165. Visual V74 freeze **interdit** (feel ≠ visual). **Passes 61–82 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse `1.8 + math.sin(time * 18) * 0.45`. **Ne pas** geler Size (visual V74 Option A, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)`. XY `0.62` / base `1.8` / freq `18` / amp `0.45` **inchangés**.

2. **Garder le pulse.** Ne **pas** poser Size = API. Ne **pas** porter V111 `frame.X`. Ne **pas** « fermer » trail / HUD / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` / `drawFlag` / `drawTerrainPreview` / `Value` (N151–N173 déjà). Ne **pas** lire `piece.part.Size` (alloc). Ne pas porter visual. Après N173. `BuildingModels` **non**. Overlay **non**. HUD **non**. Effects **non**. MainMenu **non**. VictoryScreen **non**. `createMissile` construction **non** (taille initiale `Vector3.new(0.62, 0.62, 2.3)` inchangée).

3. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N174 seulement.** N152 reste alors ouvert (feel-diverged vs V74). Ne pas inventer un cache Size. Ne pas skip-si-inchangé (N2, pas ici).

4. Tests « navires, missiles et interpolation » leftover N151 trail **et** leftover N148 mesh **et** leftover N147 Fin **doivent rester verts**. Tests « ecran de victoire » leftover N173 `valueFree` reuse **doivent rester verts**. Tests « selection de chaque nation » leftover N171 `flagFree` reuse **et** leftover N172 `previewFree` reuse **doivent rester verts**. Tests « messages rapides » leftover N170 `chatFree` reuse **doivent rester verts**. Tests « calques d'entites, effets et apercu » leftover N169 `clearActionPreview` reuse **et** leftover N168 `clearSelection` reuse **et** leftover N155 `rawequal` 2000→2001 **doivent rester verts**. Tests « vagues de conquete » leftover N167 `feedFree` reuse **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` flame **seulement**, **un** `elseif`) **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N152. Overlay **non**. **Ne pas** éditer le serveur. **Ne pas** toucher Shockwave ni BlastSmoke ni Blast sphère ni BuildRing ni HUD chat ni feed ni `Dismiss` ni `clearSelection` ni `clearActionPreview` ni `refreshChatSheet` ni `drawFlag` ni `drawTerrainPreview` ni VictoryScreen.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ N151 (trail Z) ≠ visual V74 (freeze Size=API, ne pas merger) ≠ N163 (Shockwave pool) ≠ N164 (BlastSmoke pool) ≠ N165 (Blast sphère pool) ≠ N166 (BuildRing pool) ≠ N167 (HUD feed pool) ≠ N168 (`clearSelection`) ≠ N169 (`clearActionPreview`) ≠ N170 (`refreshChatSheet` déjà) ≠ N171 (`drawFlag` déjà) ≠ N172 (`drawTerrainPreview` déjà) ≠ N173 (`VictoryScreen` `Value` déjà) ≠ N174 (`Dismiss` delay) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N174 dans le même worker. Pulse Z **conservé** — ne pas figer à 1.8. Un `elseif` flame.

---

### ISSUE-N174 — HUD `notify` delay Destroy `Dismiss` (feel)

**Priorité :** P3 alloc client HUD. Leftover explicite après N173 (`Value` déjà). Distinct de N152 (UnitModels Size), de N173 (`valueFree` podium **déjà**), de N172 (`previewFree` tuiles miniature **déjà**), de N171 (`flagFree` bandes drapeau **déjà**), de N170 (`chatFree` catalogue **déjà**), de N167 (`feedFree` TextLabel fil **déjà**), de visual V103 (préfixe `feedEntries` **fermée** sur `7188` — **ne pas merger**). `HUD.notify` **delay 4.5 s seulement**. Ne pas toucher VictoryScreen. Ne pas toucher MainMenu. Ne pas toucher Overlay. Ne pas toucher UnitModels. Ne pas toucher Effects. Ne pas retoucher `feedFree`.

**Problème :** N173 ferme le pool `Value`. N152 reste ouvert (freeze interdit). Reste, **chaque expiration de fil** (`task.delay(4.5)`, check « vagues de conquete » flush les delays, check « fil de notifications sature » court-circuite `task.delay` pour le rejet manuel) :

```
local cross = entry:FindFirstChild("Dismiss")
if cross then
    cross:Destroy()
end
```

Puis, au reuse `feedFree`, `if not entry:FindFirstChild("Dismiss")` recréé `Instance.new("TextButton")` + `Activated:Connect(removeEntry)`. Jusqu’à `MAX_FEED_ENTRIES=3` Destroy+new par rotation du fil. Distinct de leftover N152 (`Size = Vector3.new` flamme). Distinct de leftover N173 (`valueFree` **déjà** — **ne pas** partager). Distinct de leftover N167 (`feedFree` TextLabel **déjà** — **ne pas** parquer le TextLabel ici). `MAX_FEED_ENTRIES = 3` **inchangé**. Groupement **conservé**. N153 décalage préfixe **conservé**. `removeEntry` `table.remove(index)` **conservé**. Delay 4.5 s **conservé**. Garde `LayoutOrder ~= born` **conservée**.

**Piège Name :** `FindFirstChild("Dismiss")` est le contrat. Au reuse **garder** `Name = "Dismiss"`. Un pool qui pose un autre Name = croix fantôme (l’ancien n’est plus trouvé, `Instance.new` empile un second enfant). Check vagues : `pooledFeed:FindFirstChild("Dismiss") ~= nil` **doit rester vert**.

**Piège Activated :** comme N170 `chatActivated`. Au reuse, **Disconnect** l’ancien `Activated` **avant** de rebrancher `removeEntry` de **l’entrée courante**. Oubli = double-fire (le bouton parké tire encore l’ancienne `entry`). Stocker la connexion (map `dismissActivated[cross]` ou champ dédié) — **pas** `GetAttribute`. Stub banc : `Disconnect` **doit** retirer le handler (déjà, N170).

**Piège delay vs clic :** le clic `Activated` appelle `removeEntry` **avec** la croix encore enfant — `feedFree` pousse le TextLabel **avec** Dismiss. Le delay Destroy la croix **avant** le fondu, puis `removeEntry` pousse le TextLabel **sans** Dismiss. Au reuse delay : `FindFirstChild("Dismiss")` nil → pop `dismissFree`. Au reuse clic : Dismiss encore enfant → **ne pas** pop, **ne pas** empiler un second. Ne **pas** unifier les deux chemins.

**Piège feedFree :** `removeEntry` parque le TextLabel, **pas** la croix. `dismissFree` est une **liste séparée**. Ne **pas** pousser Dismiss dans `feedFree`. Ne **pas** pousser le TextLabel dans `dismissFree`. Parent Dismiss = **`entry`** (le TextLabel du fil), **pas** `self.feed`, **pas** `victory.rows`.

**Piège early-out delay :** `if not entry.Parent then return` et `LayoutOrder ~= born` **conservés**. Un delay fantôme ne doit **pas** parker la croix d’un message reparenté (plafond N153 recycle avant 4.5 s). Parker **seulement** si les deux gardes passent.

**Pourquoi 20K CCU :** leftover N173. 8 clients × fil 10 Hz × Destroy+new de TextButton Dismiss. Pas d’autorité (cosmétique fil). `valueFree` **déjà** N173 — ne pas y revenir. Visual V103 préfixe **interdit** (fermée sur `7188`, ne pas merger). **Oubli de Name=Dismiss** = croix empilées. **Oubli Disconnect** = double-rejet. **Si le seul patch est un merger visuel : ne pas livrer.**

**Worker :**

1. Dans `HUD.notify` delay 4.5 s seulement : **ne plus** `Destroy` le TextButton `Dismiss`. `Parent = nil` + push `dismissFree` (nommer **`dismissFree`**, pas `valueFree` / `previewFree` / `flagFree` / `chatFree` / `feedFree`). Pop O(1) depuis la fin au reuse `if not entry:FindFirstChild("Dismiss")`. Si vide : `Instance.new("TextButton")` **une fois** comme aujourd’hui, puis poser Name/Anchor/Position/Size/BackgroundTransparency/FontFace/TextSize/TextColor3/Text/ZIndex. Au reuse : reset ces champs + `Name = "Dismiss"`. `Parent = entry` (le TextLabel, **pas** `self.feed`, **pas** `hud.chatBody`). **Sauter** UICorner / UIStroke (Dismiss n’en a pas). Disconnect Activated **avant** rebranchement. Garde Parent / LayoutOrder **conservées**. `removeEntry` **inchangé**.

2. **Garder les croix.** Ne **pas** recréer après le reuse `feedFree` si `Dismiss` est encore enfant (chemin clic). Ne **pas** changer `Name`. Ne **pas** toucher N173 `valueFree`. Ne **pas** toucher N167 `feedFree` (le TextLabel). Ne **pas** toucher MainMenu. Après N173. Flame **non** (N152). Overlay **non**. Effects **non**. `BuildingModels` **non**. VictoryScreen **non**. Parent = **`entry`** obligatoire au reuse.

3. Tests « vagues de conquete » leftover N167 `feedFree` reuse **doivent rester verts** (`pooledFeed:FindFirstChild("Dismiss") ~= nil` **obligatoire**). **Ajouter** : snapshot le TextButton `Dismiss` de `pooledFeed` **après** `hud:notify("n167 reuse")` **avant** un second `testFlushDelays` **ou** un second notify qui recycle — `rawequal` du TextButton réparenté **ou** présence dans `dismissFree` — au choix, **pas** d’assert autre Name, **pas** `#dismissFree == 3`. Tests « fil de notifications sature » leftover N153 / N167 **doivent rester verts** (court-circuit `task.delay` **conservé** — ne pas flush ici). Tests « ecran de victoire » leftover N173 **doivent rester verts**. Tests « selection de chaque nation » leftover N171 **et** leftover N172 **doivent rester verts**. Tests « messages rapides » leftover N170 **doivent rester verts**. Tests « calques d'entites, effets et apercu » leftover N169 / N168 / N155 **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client `vagues de conquete` **doit rester vert**. Check fil leftover N153 / N167 **sans** flush. Check ecran leftover N173. Check selection leftover N172 / N171. Check messages rapides leftover N170. Check calques leftover N169 / N168. Check navires leftover N152 flame. **Ne pas** casser N173 (`valueFree` snapshot + reuse `rawequal` Parent row **ou** free-list). **Ne pas** casser N172 (`previewFree` snapshot + reuse Parent `featuredPreview` **ou** free-list, shade frère). **Ne pas** casser N171 (`flagFree` snapshot + reuse Parent `playerFlag` **ou** free-list, UICorner parent, Rotation 0). **Ne pas** casser N170 (`chatFree` snapshot + reuse Parent `hud.chatBody`, un `UIGridLayout`). **Ne pas** casser N169 (`self.actionPreview` conservé). **Ne pas** casser N168 (`self.selection` conservé). **Ne pas** casser N167 (`feedFree`). Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `HUD.luau` (`notify` delay **seulement**, helper reuse à côté du module — **liste séparée** `dismissFree`). `tests/client.luau` **seulement** le check « vagues de conquete » (commentaire leftover N174, **ajouter** snapshot + reuse si possible, **garder** `FindFirstChild("Dismiss") ~= nil` + `testFlushDelays` existant). `VictoryScreen.luau` **non**. `MainMenu.luau` **non**. `Effects.luau` **non**. `Overlay.luau` **non**. `UnitModels.luau` **non**. `drawTerrainPreview` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher flame ni Blast ni HUD chat ni `feedFree` ni `clearSelection` ni `clearActionPreview` ni `flagFree` ni `previewFree` ni `valueFree`. **Ne pas** merger visual V103 (`7188`).

**Contraintes :** pas de RemoteFunction. **N174 feel ≠ N173 (`VictoryScreen` `Value` déjà) ≠ N172 (`drawTerrainPreview` déjà) ≠ N171 (`drawFlag` déjà) ≠ N170 (`refreshChatSheet` déjà) ≠ N167 (HUD feed pool déjà) ≠ N152 (flame Size, ne pas freeze V74) ≠ visual V103 (HUD préfixe fermée `7188`, ne pas merger) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N152 dans le même worker. Free-list **`dismissFree`** — **pas** `feedFree`. **Pas Destroy** des TextButton `Dismiss`. **Pas de parcours de `self.feed`.** **Reset Name / Activated Disconnect.** Distinct `valueFree` / `previewFree` / `flagFree` / `chatFree` / `feedFree` — **ne pas** partager. Parent `entry` **obligatoire**. `Name = "Dismiss"` **obligatoire**. HUD N167 `feedFree` **obligatoire** inchangé. `Value` N173 **obligatoire** inchangé. Early-out delay Parent / LayoutOrder **obligatoire** inchangé.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; HUD feed → **N167 fait** ; `clearSelection` → **N168 fait** ; `clearActionPreview` → **N169 fait** ; `refreshChatSheet` → **N170 fait** ; `drawFlag` → **N171 fait** ; `drawTerrainPreview` → **N172 fait** ; `Value` → **N173 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (… ; HUD feed pool → **N167** ; `clearSelection` → **N168** ; `clearActionPreview` → **N169** ; `refreshChatSheet` → **N170** ; `drawFlag` → **N171** ; `drawTerrainPreview` → **N172** ; `Value` → **N173** ; Overlay explosion + chantier + fil clos ; HUD `Dismiss` delay = **N174**) |
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
| N34–N151, N153–N173 | (voir rapport #223) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–82) |
| N174 | HUD `notify` delay Destroy `Dismiss` | P3 | **nouveau** (`dismissFree`, pas `feedFree`, Name `Dismiss` conservé, Disconnect Activated, Parent `entry`, N173 podium **déjà**, delay vs clic distincts, **≠** visual V103 fermée `7188`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 / #167 / #169 / #171 / #173 / #176 / #178 / #181 / #183 / #185 / #187 / #189 / #191 / #193 / #195 / #197 / #200 / #202 / #204 / #206 / #208 / #210 / #213 / #214 / #216 / #219 / #221 / #223 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N173 `Value` pool) |

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
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.33 p95TickMs=0.73
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `selection de chaque nation et de chaque mode` leftover N171 `flagFree` snapshot Frame `playerFlag` + reuse Parent **ou** free-list + UICorner parent intact + Rotation diagonal→vertical = 0 **et** leftover N172 `previewFree` snapshot Frame `featuredPreview` + reuse Parent **ou** free-list + shade frère UIGradient intact / Nations+GameModes **gardés** ; `salon : la carte en direct` `setLobby` × 4 (refreshFeatured via pool) ; `fil de notifications sature` leftover N153 / leftover N167 commentaire **sans** flush ; `messages rapides` leftover N170 `chatFree` snapshot + reuse Parent `hud.chatBody` + un `UIGridLayout` + envoi `social_gg` / `attack_target` slot 3 ; `calques d'entites, effets et apercu` leftover N155 reuse / leftover N168 `clearSelection` Parent nil + reselect `effects.root` / leftover N169 `clearActionPreview` Parent nil + re-preview `effects.root` ; `hover spawn isolation` leftover N58 ; `construction du monde 3D` leftover N137/N138 ; `pose et capture de chaque type de batiment` leftover N136 / leftover N132 / leftover N162 commentaire **sans** flush / leftover N166 commentaire **sans** flush / leftover N167 commentaire ; `modeles procéduraux` leftover N150/N149 ; `apercu de placement pour chaque batiment` leftover N129 ; `livraison : le gain s'affiche sur la gare` leftover N159 **sans** flush ; `navires, missiles et interpolation` leftover N151 trail / leftover N152 flame Size / leftover N148 mesh / leftover N160 wake **sans** flush / leftover N161 splash **sans** flush / leftover N163 Shockwave **sans** flush / leftover N164 BlastSmoke **sans** flush / leftover N165 Blast **sans** flush, skip retraite id=1 N56 ; `vagues de conquete` N167 `feedFree` reuse (`testFlushDelays` → `#feedFree >= 1` **avant** N160, `hud:notify` texte nouveau `rawequal` Parent `hud.feed`, Dismiss recréé, `# == feedN - 1`) / leftover N166 `BuildRing` reuse / leftover N165 `Blast` reuse / leftover N164 `BlastSmoke` reuse / leftover N163 `Shockwave` reuse / leftover N162 `DeliveryPulse` reuse / leftover N161 `LandingSplash` reuse / leftover N160 `LaunchWake` reuse / leftover N159 `goldPopup` reuse / leftover N158 `floatingText` reuse / leftover N157 `conquestPulse` reuse / leftover N156 `tileFlash` reuse ; `ecran de victoire` leftover N173 `valueFree` snapshot TextLabel `Value` `rows[1]` + reuse Parent row **ou** free-list, deux `show` + `hide` + `setCountdown`. Serveur **non** touché cette passe. `UnitModels.luau` **non** touché. `WorldCamera.luau` **non** touché. Overlay **non** touché. BuildingModels **non** touché. Effects **non** touché. HUD **non** touché. MainMenu **non** touché. Pulse flamme Size **inchangé** (N152). HUD `Dismiss` delay Destroy **inchangé** (N174). VictoryScreen `Value` **poolé**. MainMenu `drawTerrainPreview` **poolé**. MainMenu `drawFlag` **poolé**. HUD `refreshChatSheet` **poolé**. Stub `Disconnect` **inchangé**.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass82.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N173 est un recycle TextLabel VictoryScreen vérifié par le banc headless (`ecran de victoire` snapshot + reuse Parent row **ou** `valueFree`). Pulse flamme Size **inchangé** (N152). HUD `Dismiss` delay Destroy **inchangé** (N174).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N173 n’ajoute **pas** de require (référence locale VictoryScreen `valueFree`). Intro continue de `require` MainMenu pour `drawFlag` (déjà). N152 restera dans `UnitModels.place` flame. N174 restera dans `HUD.notify` delay.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Distinct trail N151. Distinct Overlay N163–N165 **déjà**. Distinct BuildRing N166 **déjà**. Distinct HUD N167 **déjà**. Distinct `clearSelection` N168 **déjà**. Distinct `clearActionPreview` N169 **déjà**. Distinct `refreshChatSheet` N170 **déjà**. Distinct MainMenu `drawFlag` N171 **déjà**. Distinct MainMenu `drawTerrainPreview` N172 **déjà**. Distinct leftover N173 **déjà**. Distinct leftover N174. Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N170 : `HUD.refreshChatSheet` seulement. **Pas** Destroy des TextButton. Free-list `chatFree` (pas `feedFree`). **Garder** le `UIGridLayout` (ne pas en recréer un). **Disconnect** `Activated` avant rebranchement (oubli = double-fire, test « messages rapides » rouge). Parent `self.chatBody`. Ne **pas** `Theme.corner` / `Theme.stroke` au reuse. MouseEnter/Leave **conservés**. Dismiss delay Destroy **conservé** (leftover N174). Distinct N167 `feedFree`. Distinct N169 preview. Distinct visual V103 (ne pas merger `7188`). **Ne pas** flush. **Ne pas** casser N169 ni N168 ni N167 ni N154. Catalogue vs pending **inchangé**. Stub banc : `Disconnect` **doit** retirer le handler (no-op = Fire accumule).

Piège N171 : `MainMenu.drawFlag` seulement. **Pas** Destroy des Frame bandes. Free-list `flagFree` (pas `chatFree`). **Garder** le UICorner du parent (filtre `IsA("Frame")`). **Reset Rotation** (diagonal `-30` vs vertical `0`). Parent = argument `parent` (quatre call sites + Intro). Distinct N170 `chatFree`. Distinct N172 `previewFree`. Distinct visual V107 (ne pas merger `ee95`). **Ne pas** flush. **Ne pas** casser N170 ni N169 ni N168 ni N167. Motifs **inchangés**.

Piège N172 : `MainMenu.drawTerrainPreview` seulement. **Pas** Destroy des Frame tuiles. Free-list `previewFree` (pas `flagFree`). **Ne pas** parcourir la carte / `shade` (frère du preview). **Reset Size / ZIndex**. Parent = argument `frame`. Océan non dessiné. Distinct N171 `flagFree`. Distinct visual V108 (ne pas merger `d46a`). **Ne pas** flush. **Ne pas** casser N171 ni N170 ni N169 ni N168 ni N167. `MapGen.generate` **conservé**.

Piège N173 : `VictoryScreen.show` seulement. **Pas** Destroy des TextLabel `Value`. Free-list `valueFree` (pas `previewFree`). **Garder** `Name = "Value"`. **Reset TextXAlignment = Right**. Parent = `row` (`self.rows[i]`). Early-out Visible **conservé**. Ligne sans item : parker `Value`. Distinct N172 `previewFree`. Distinct visual V110 (fermée `9726`, ne pas merger). **Ne pas** flush. **Ne pas** casser N172 ni N171 ni N170 ni N169 ni N168 ni N167. `hide` **inchangé**.

Piège N174 (à venir) : `HUD.notify` delay seulement. **Pas** Destroy des TextButton `Dismiss`. Free-list `dismissFree` (pas `feedFree`). **Garder** `Name = "Dismiss"`. **Disconnect** Activated avant rebranchement. Parent = `entry` (le TextLabel). Delay vs clic **distincts** (clic laisse Dismiss enfant). Distinct N173 `valueFree`. Distinct visual V103 (fermée `7188`, ne pas merger). **Ne pas** flush dans « fil de notifications sature ». **Ne pas** casser N173 ni N172 ni N171 ni N170 ni N169 ni N168 ni N167. `removeEntry` **inchangé**. Check vagues `FindFirstChild("Dismiss") ~= nil` **obligatoire**.
