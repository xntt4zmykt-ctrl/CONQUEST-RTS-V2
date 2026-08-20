--!strict
--[[
	Mise en forme des nombres.

	Un seul endroit, parce que ces chiffres apparaissent maintenant a trois
	endroits qui doivent absolument s'accorder : le classement Roblox, les
	etiquettes posees sur la carte, et le bandeau du HUD. Trois formatages
	ecrits separement finissent toujours par diverger — le joueur lit alors
	87.5K sur la carte et 87 500 dans le classement, et se demande lequel ment.

	La regle est celle du jeu de reference : **trois chiffres significatifs**,
	puis un suffixe. C'est ce qui produit 5.50K, 39.8K, 683K, 1.29M — la largeur
	de la colonne ne bouge jamais, quel que soit l'ordre de grandeur.
]]

local Format = {}

--[[
	Trois chiffres significatifs pour une mantisse comprise entre 1 et 999.

	Le nombre de decimales depend de la partie entiere, pas d'une regle fixe :
	c'est ce qui garde une largeur constante a l'affichage.
]]
local function significant(value: number): string
	if value >= 100 then
		return string.format("%.0f", value)
	elseif value >= 10 then
		return string.format("%.1f", value)
	end
	return string.format("%.2f", value)
end

--[[
	Forme compacte : 87.5K, 1.29M, 4.06B.

	En dessous de mille on affiche l'entier tel quel — abreger 543 en 0.54K
	serait a la fois plus long et moins precis.
]]
function Format.compact(value: number): string
	local sign = if value < 0 then "-" else ""
	local magnitude = math.abs(value)

	if magnitude >= 1e9 then
		return sign .. significant(magnitude / 1e9) .. "B"
	elseif magnitude >= 1e6 then
		return sign .. significant(magnitude / 1e6) .. "M"
	elseif magnitude >= 1e3 then
		return sign .. significant(magnitude / 1e3) .. "K"
	end
	return sign .. string.format("%.0f", magnitude)
end

--[[
	Part de territoire, en pourcentage.

	Une decimale et pas zero : en debut de partie tout le monde est sous 1 %, et
	un entier afficherait douze factions a "0 %" — soit exactement l'information
	que la colonne existe pour donner.
]]
function Format.percent(part: number, whole: number): string
	if whole <= 0 then
		return "0.0%"
	end
	return string.format("%.1f%%", part / whole * 100)
end

return Format
