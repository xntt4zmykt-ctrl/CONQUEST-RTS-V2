--!strict
--[[
	Classement Roblox natif.

	Le jeu a deja son propre classement a l'ecran, mais celui de Roblox — la
	liste ouverte par Tab, ou par le bouton en haut a droite sur mobile — est
	celui que les joueurs consultent par reflexe, et le seul visible depuis le
	menu d'echappement. Y publier le territoire et l'armee coute trois
	StringValue par joueur et rend la partie lisible sans ouvrir aucun panneau
	du jeu.

	Roblox impose le nom `leaderstats` et lit les valeurs enfants dans l'ordre
	de creation : territoire d'abord, puisque c'est lui qui decide la victoire.

	Le module est separe du point d'entree serveur parce que ce dernier est
	exclu du banc d'essai : la logique y etait invisible aux tests, et une
	regression sur les colonnes ne plante rien — elle affiche simplement des
	valeurs fausses dans la liste que tout le monde regarde.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local GameState = require(script.Parent.GameState)

type GameState = GameState.GameState
type PlayerState = GameState.PlayerState

local Leaderstats = {}

--[[
	Colonnes publiees dans la liste des joueurs.

	Roblox affiche le **nom de l'objet** comme en-tete de colonne et sa `Value`
	dans la cellule : c'est tout ce que l'API permet. Pas de couleur, pas de
	police, pas d'icone dans l'en-tete, pas de colonne de rang. Les emoji, eux,
	passent — ce sont des caracteres comme les autres — ce qui donne des
	en-tetes lisibles sans y coller trois mots.

	Ce sont des StringValue et pas des IntValue, et ce choix a un cout qu'il
	faut connaitre : Roblox trie la liste sur la premiere valeur **numerique**.
	En StringValue, on perd le tri automatique et on gagne "1.29M" au lieu de
	"1290000". Le compromis se discute — repasser la premiere colonne en
	IntValue rendrait le tri et suffirait a inverser la decision.

	L'ordre de cette table EST l'ordre des colonnes a l'ecran : la liste des
	joueurs n'offre aucun autre levier de rangement.
]]
Leaderstats.COLUMNS = {
	{ key = "share", name = "\u{1F5FA}\u{FE0F}" }, -- part du territoire
	{ key = "gold", name = "\u{1FA99}" }, -- or
	{ key = "troops", name = "\u{2694}\u{FE0F}" }, -- armee
}

-- Valeur affichee tant qu'aucun tick n'a encore publie l'etat du joueur. Un
-- tiret plutot que "0" : la difference entre "pas encore mesure" et "reduit a
-- rien" est justement ce que la colonne existe pour montrer.
local PLACEHOLDER = "-"

--[[
	Cree le dossier `leaderstats` et ses colonnes, une seule fois par joueur.

	Idempotent : rappeler la fonction sur un joueur deja equipe renvoie le
	dossier existant sans rien recreer. C'est indispensable parce que la
	publication passe par ici a chaque tick de seconde, et que dupliquer les
	colonnes remplirait la liste de doublons irrecuperables.
]]
function Leaderstats.ensure(player: Player): Folder
	local existing = player:FindFirstChild("leaderstats")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	for _, column in Leaderstats.COLUMNS do
		local value = Instance.new("StringValue")
		value.Name = column.name
		value.Value = PLACEHOLDER
		-- L'attribut porte l'identite de la colonne, pas son nom : les noms
		-- sont des emoji, et s'en servir comme cle couplerait la mise a jour a
		-- un choix d'icone qu'on voudra changer un jour.
		value:SetAttribute("Key", column.key)
		value.Parent = folder
	end

	-- Parente en dernier : les colonnes existent deja quand la replication
	-- part, donc le client ne voit jamais une liste a moitie construite.
	folder.Parent = player
	return folder
end

--[[
	Recopie l'etat d'un joueur dans ses colonnes.

	On retrouve la colonne par son attribut `Key` et non par son nom, pour la
	raison ci-dessus. Le formatage vient de Format et de nulle part ailleurs :
	le HUD et les etiquettes de la carte affichent les memes nombres, et deux
	arrondis differents feraient douter le joueur de celui qui ment.
]]
function Leaderstats.apply(player: Player, ps: PlayerState, landCount: number)
	local folder = Leaderstats.ensure(player)

	for _, child in folder:GetChildren() do
		if not child:IsA("StringValue") then
			continue
		end
		local key = child:GetAttribute("Key")
		if key == "share" then
			child.Value = Format.percent(ps.tiles, landCount)
		elseif key == "gold" then
			child.Value = Format.compact(ps.gold)
		elseif key == "troops" then
			child.Value = Format.compact(ps.troops)
		end
	end
end

--[[
	Efface les colonnes d'un joueur qui n'a plus de faction.

	Sans cet effacement, les colonnes gelaient sur leur derniere valeur : un
	joueur elimine mais toujours connecte continuait d'afficher le territoire
	qu'il ne possede plus, et son armee morte. La colonne disait alors
	exactement le contraire de ce pour quoi elle existe — et rien ne le
	signalait, puisque des chiffres plausibles restaient a l'ecran.

	On efface plutot que de supprimer le dossier : un joueur elimine peut
	reapparaitre au match suivant, et recreer les colonnes a chaque fois les
	ferait clignoter dans la liste.
]]
local ELIMINATED = "\u{2014}"

function Leaderstats.clear(player: Player)
	local folder = Leaderstats.ensure(player)
	for _, child in folder:GetChildren() do
		if child:IsA("StringValue") then
			child.Value = ELIMINATED
		end
	end
end

--[[
	Publie l'etat de tous les joueurs connectes.

	Un joueur present dans `slotByPlayer` mais absent de `state.players` a perdu
	sa faction : ses colonnes sont effacees, pas laissees en l'etat.
]]
function Leaderstats.publish(state: GameState, slotByPlayer: { [Player]: number })
	for player, slot in slotByPlayer do
		local ps = state.players[slot]
		if ps then
			Leaderstats.apply(player, ps, state.landCount)
		else
			Leaderstats.clear(player)
		end
	end
end

return Leaderstats
