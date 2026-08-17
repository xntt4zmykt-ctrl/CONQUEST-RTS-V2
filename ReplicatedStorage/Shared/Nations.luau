--!strict
--[[
	Nations jouables.

	Chaque nation est un nom et un drapeau. Les drapeaux sont **dessines**
	(bandes, croix, diagonales) plutot qu'importes : aucun asset a uploader,
	aucune moderation a attendre, et ils restent nets a toutes les tailles.

	Note de conception : la couleur du drapeau ne determine pas la couleur du
	territoire sur la carte. Celle-ci reste attribuee par emplacement, parce
	qu'elle doit garantir que deux empires voisins soient toujours
	distinguables — si douze joueurs choisissaient tous du rouge, la carte
	deviendrait illisible. Le drapeau est l'identite, la couleur de carte est un
	outil de lecture.
]]

export type Flag = {
	-- "vertical" | "horizontal" | "cross" | "diagonal" | "quarters"
	pattern: string,
	colors: { Color3 },
}

export type Nation = {
	id: number,
	name: string,
	flag: Flag,
}

local Nations = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Nations.LIST = {
	{ id = 1, name = "Valoria", flag = { pattern = "vertical", colors = { rgb(198, 40, 40), rgb(245, 245, 245), rgb(30, 60, 140) } } },
	{ id = 2, name = "Kerensk", flag = { pattern = "horizontal", colors = { rgb(240, 240, 240), rgb(40, 90, 190), rgb(190, 35, 40) } } },
	{ id = 3, name = "Odaria", flag = { pattern = "cross", colors = { rgb(20, 70, 150), rgb(250, 210, 60) } } },
	{ id = 4, name = "Thane", flag = { pattern = "diagonal", colors = { rgb(30, 35, 45), rgb(200, 60, 50) } } },
	{ id = 5, name = "Miravel", flag = { pattern = "horizontal", colors = { rgb(40, 160, 90), rgb(250, 250, 250), rgb(40, 160, 90) } } },
	{ id = 6, name = "Sarkhad", flag = { pattern = "vertical", colors = { rgb(20, 25, 35), rgb(225, 160, 40), rgb(20, 25, 35) } } },
	{ id = 7, name = "Belmara", flag = { pattern = "quarters", colors = { rgb(180, 40, 90), rgb(245, 240, 230) } } },
	{ id = 8, name = "Nordhal", flag = { pattern = "cross", colors = { rgb(235, 235, 240), rgb(30, 80, 160) } } },
	{ id = 9, name = "Ozrek", flag = { pattern = "diagonal", colors = { rgb(90, 45, 140), rgb(240, 200, 70) } } },
	{ id = 10, name = "Cyrenne", flag = { pattern = "horizontal", colors = { rgb(50, 170, 190), rgb(245, 245, 245), rgb(230, 130, 50) } } },
	{ id = 11, name = "Draska", flag = { pattern = "vertical", colors = { rgb(120, 30, 40), rgb(35, 35, 40), rgb(190, 150, 60) } } },
	{ id = 12, name = "Ashvale", flag = { pattern = "quarters", colors = { rgb(60, 130, 60), rgb(30, 40, 55) } } },
	{ id = 13, name = "Portane", flag = { pattern = "horizontal", colors = { rgb(220, 90, 40), rgb(240, 235, 220) } } },
	{ id = 14, name = "Ismera", flag = { pattern = "cross", colors = { rgb(200, 50, 80), rgb(250, 245, 235) } } },
	{ id = 15, name = "Vantak", flag = { pattern = "diagonal", colors = { rgb(25, 90, 110), rgb(230, 235, 240) } } },
	{ id = 16, name = "Rhodemar", flag = { pattern = "vertical", colors = { rgb(240, 220, 90), rgb(40, 45, 60), rgb(200, 70, 60) } } },
} :: { Nation }

function Nations.get(id: number): Nation
	for _, nation in Nations.LIST do
		if nation.id == id then
			return nation
		end
	end
	return Nations.LIST[1]
end

return Nations
