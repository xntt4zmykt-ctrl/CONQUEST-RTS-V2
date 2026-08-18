--!strict
--[[
	Catalogue sonore.

	IMPORTANT — les identifiants ci-dessous sont les sons **integres au moteur**
	Roblox (`rbxasset://sounds/...`). Ils ne necessitent aucun upload et
	fonctionnent immediatement, mais ce sont des sons utilitaires generiques :
	ils servent de doublure pour que le jeu ait un retour audible des
	maintenant, pas de design sonore final.

	Pour passer a du vrai son : remplacer `id` par un `rbxassetid://...` depuis
	le Creator Store. Ne rien changer d'autre — le reste du systeme est
	indifferent a la provenance.

	Un `id` vide desactive proprement le son, sans erreur : c'est ce qui permet
	de retirer une doublure sans casser le jeu.
]]

export type SoundDef = {
	id: string,
	volume: number,
	-- Variation aleatoire de hauteur, en demi-tons de part et d'autre. Sans
	-- elle, un son declenche en rafale (capture de tuiles) devient une
	-- mitraillette insupportable.
	pitchRange: number,
	-- Duree minimale entre deux declenchements du meme son, en secondes.
	throttle: number,
	category: string,
}

local Audio = {}

Audio.CATEGORY = {
	UI = "ui",
	GAME = "game",
	ALERT = "alert",
}

Audio.SOUNDS = {
	--=========================================================================
	-- Interface
	--=========================================================================
	uiClick = {
		id = "rbxasset://sounds/volume_slider.ogg",
		volume = 0.28,
		pitchRange = 0.5,
		throttle = 0.04,
		category = "ui",
	},
	uiSelect = {
		id = "rbxasset://sounds/volume_slider.ogg",
		volume = 0.22,
		pitchRange = 0.6,
		throttle = 0.05,
		category = "ui",
	},
	uiError = {
		id = "rbxasset://sounds/ouch.ogg",
		volume = 0.18,
		pitchRange = 0.2,
		throttle = 0.15,
		category = "ui",
	},

	--=========================================================================
	-- Actions de jeu
	--=========================================================================
	attackLaunch = {
		id = "rbxasset://sounds/action_falling.ogg",
		volume = 0.5,
		pitchRange = 1.5,
		throttle = 0.12,
		category = "game",
	},
	-- Declenche a chaque vague de captures. Fortement bride et tres variable
	-- en hauteur : c'est le son le plus frequent du jeu, il doit rester une
	-- texture de fond et jamais attirer l'attention.
	tileCapture = {
		id = "rbxasset://sounds/action_jump_land.mp3",
		volume = 0.12,
		pitchRange = 3.0,
		throttle = 0.09,
		category = "game",
	},
	buildPlace = {
		id = "rbxasset://sounds/action_jump_land.mp3",
		volume = 0.45,
		pitchRange = 0.8,
		throttle = 0.05,
		category = "game",
	},
	boatLaunch = {
		id = "rbxasset://sounds/impact_water.mp3",
		volume = 0.5,
		pitchRange = 0.8,
		throttle = 0.1,
		category = "game",
	},
	boatLand = {
		id = "rbxasset://sounds/impact_water.mp3",
		volume = 0.45,
		pitchRange = 0.8,
		throttle = 0.1,
		category = "game",
	},

	--=========================================================================
	-- Evenements majeurs
	--=========================================================================
	nukeLaunch = {
		id = "rbxasset://sounds/action_falling.ogg",
		volume = 0.75,
		pitchRange = 0.3,
		throttle = 0.3,
		category = "alert",
	},
	nukeImpact = {
		id = "rbxasset://sounds/impact_explosion_03.mp3",
		volume = 0.9,
		pitchRange = 0.4,
		throttle = 0.2,
		category = "alert",
	},
	samIntercept = {
		id = "rbxasset://sounds/impact_explosion_03.mp3",
		volume = 0.55,
		pitchRange = 1.0,
		throttle = 0.15,
		category = "alert",
	},
	allianceFormed = {
		id = "rbxasset://sounds/volume_slider.ogg",
		volume = 0.5,
		pitchRange = 0.2,
		throttle = 0.3,
		category = "alert",
	},
	betrayal = {
		id = "rbxasset://sounds/ouch.ogg",
		volume = 0.6,
		pitchRange = 0.2,
		throttle = 0.3,
		category = "alert",
	},
	capitalFallen = {
		id = "rbxasset://sounds/impact_explosion_03.mp3",
		volume = 0.8,
		pitchRange = 0.2,
		throttle = 0.3,
		category = "alert",
	},
	eraAdvance = {
		id = "rbxasset://sounds/action_get_up.mp3",
		volume = 0.6,
		pitchRange = 0,
		throttle = 0.5,
		category = "alert",
	},
	victory = {
		id = "rbxasset://sounds/action_get_up.mp3",
		volume = 0.8,
		pitchRange = 0,
		throttle = 1,
		category = "alert",
	},
	defeat = {
		id = "rbxasset://sounds/oof.ogg",
		volume = 0.7,
		pitchRange = 0,
		throttle = 1,
		category = "alert",
	},
} :: { [string]: SoundDef }

-- Volume par categorie, exposé pour un futur menu de reglages.
Audio.categoryVolume = {
	ui = 0.8,
	game = 1.0,
	alert = 1.0,
}

Audio.masterVolume = 0.75

return Audio
