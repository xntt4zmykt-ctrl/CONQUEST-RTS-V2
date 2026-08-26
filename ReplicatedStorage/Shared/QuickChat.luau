--!strict
--[[
	Messages rapides predefinis, regle CONQUEST.

	Sur Roblox, les joueurs d'une meme partie ne parlent souvent pas la meme
	langue : le free-chat est un luxe, la coordination passe par des messages
	predefinis que tout le monde peut lire. Chaque message a une portee —
	coordination d'alliance ou annonce publique — et certains exigent une cible,
	designee en meme temps pour toute l'alliance (voir Diplomacy.setTargetMark).

	Les textes sont les notres ; seules les categories reprennent l'esprit du
	regles CONQUEST.
]]

local QuickChat = {}

-- Anti-spam : un message par joueur toutes les trois secondes.
QuickChat.COOLDOWN = 30 -- ticks

export type Message = {
	id: string,
	category: string,
	text: string, -- "{target}" est remplace par le nom du joueur designe
	needsTarget: boolean,
	alliesOnly: boolean, -- coordination discrete vs annonce publique
	mark: boolean, -- designe aussi la cible pour toute l'alliance
}

local function msg(id: string, category: string, text: string, needsTarget: boolean, alliesOnly: boolean, mark: boolean?): Message
	return {
		id = id,
		category = category,
		text = text,
		needsTarget = needsTarget,
		alliesOnly = alliesOnly,
		mark = mark == true,
	}
end

QuickChat.CATEGORIES = {
	{ id = "aide", name = "Aide" },
	{ id = "attaque", name = "Attaque" },
	{ id = "defense", name = "Defense" },
	{ id = "alerte", name = "Alerte" },
	{ id = "social", name = "Social" },
}

QuickChat.MESSAGES = {
	-- Aide : la demande d'assistance reste entre allies, la supplier en public
	-- reviendrait a annoncer ses faiblesses a ses predateurs.
	msg("help_troops", "aide", "J'ai besoin de troupes !", false, true),
	msg("help_gold", "aide", "J'ai besoin d'or !", false, true),
	msg("help_defend", "aide", "Aidez-moi a repousser {target} !", true, true),
	msg("help_peace", "aide", "Je ne cherche pas la guerre.", false, false),

	-- Attaque : les deux premiers messages designent la cible pour toute
	-- l'alliance — c'est ce qui transforme trois offensives desordonnees en
	-- une offensive coordonnee.
	msg("attack_target", "attaque", "Attaquez {target} !", true, true, true),
	msg("attack_focus", "attaque", "Concentrez vos forces sur {target} !", true, true, true),
	msg("attack_finish", "attaque", "Achevez {target} !", true, true),
	msg("attack_nuke", "attaque", "Frappez {target} au nucleaire !", true, true),

	-- Defense.
	msg("defend_border", "defense", "Renforcez ma frontiere !", false, true),
	msg("defend_spare", "defense", "N'attaquez pas {target}, on en a besoin.", true, true),
	msg("defend_sam", "defense", "Construisez des defenses anti-aeriennes !", false, true),

	-- Alertes publiques : designer un danger, c'est aussi de la diplomatie.
	msg("warn_big", "alerte", "{target} devient trop puissant !", true, false),
	msg("warn_mirv", "alerte", "{target} prepare une frappe majeure !", true, false),
	msg("warn_traitor", "alerte", "Mefiez-vous de {target}, c'est un traitre !", true, false),

	-- Social : la politesse des fins de partie.
	msg("social_gg", "social", "Bien joue !", false, false),
	msg("social_luck", "social", "Bonne chance a tous !", false, false),
	msg("social_thanks", "social", "Merci !", false, false),
	msg("social_oops", "social", "Oups...", false, false),
}

local byId: { [string]: Message } = {}
for _, entry in QuickChat.MESSAGES do
	byId[entry.id] = entry
end

function QuickChat.get(id: string): Message?
	return byId[id]
end

function QuickChat.format(entry: Message, targetName: string?): string
	local text = entry.text
	if targetName then
		text = string.gsub(text, "{target}", targetName)
	end
	return text
end

return QuickChat
