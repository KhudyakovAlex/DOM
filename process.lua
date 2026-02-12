-- Tilemaker process script with address support
-- Compatible with ghcr.io/systemed/tilemaker:master

-- Nodes we care about
node_keys = { "place", "amenity", "shop", "addr:housenumber" }

function node_function()
	local place = Find("place")
	local name = Find("name")
	
	-- Places
	if place ~= "" and name ~= "" then
		Layer("place", false)
		Attribute("name", name)
		Attribute("name:latin", Find("name:en") ~= "" and Find("name:en") or name)
		Attribute("class", place)
		if place == "city" then MinZoom(3)
		elseif place == "town" then MinZoom(6)
		elseif place == "village" then MinZoom(9)
		else MinZoom(11) end
	end
	
	-- Housenumbers from nodes
	local housenumber = Find("addr:housenumber")
	if housenumber ~= "" then
		Layer("housenumber", false)
		Attribute("housenumber", housenumber)
		local street = Find("addr:street")
		if street ~= "" then Attribute("addr:street", street) end
	end
	
	-- POI
	local amenity = Find("amenity")
	local shop = Find("shop")
	if amenity ~= "" or shop ~= "" then
		Layer("poi", false)
		if name ~= "" then Attribute("name", name) end
		Attribute("class", amenity ~= "" and amenity or shop)
	end
end

function way_function()
	local highway = Find("highway")
	local waterway = Find("waterway")
	local water = Find("water")
	local natural = Find("natural")
	local landuse = Find("landuse")
	local leisure = Find("leisure")
	local building = Find("building")
	local boundary = Find("boundary")
	local name = Find("name")
	
	local isClosed = IsClosed()
	
	-- Buildings with addresses
	if building ~= "" then
		Layer("building", true)
		
		-- Height
		local height = Find("height")
		local levels = Find("building:levels")
		local renderHeight = 10
		if height ~= "" then
			local h = tonumber(height:match("^([%d%.]+)"))
			if h then renderHeight = h end
		elseif levels ~= "" then
			local l = tonumber(levels)
			if l then renderHeight = l * 3 end
		end
		AttributeNumeric("render_height", renderHeight)
		AttributeNumeric("render_min_height", 0)
		
		-- ADDRESS FIELDS - key addition!
		local addr_street = Find("addr:street")
		local addr_housenumber = Find("addr:housenumber")
		local addr_city = Find("addr:city")
		
		if addr_street ~= "" then
			Attribute("addr:street", addr_street)
		end
		if addr_housenumber ~= "" then
			Attribute("addr:housenumber", addr_housenumber)
		end
		if addr_city ~= "" then
			Attribute("addr:city", addr_city)
		end
		
		MinZoom(13)
	end
	
	-- Roads
	if highway ~= "" then
		if highway == "motorway" or highway == "trunk" or highway == "primary" or 
		   highway == "secondary" or highway == "tertiary" or highway == "residential" or
		   highway == "unclassified" or highway == "service" then
			Layer("transportation", false)
			Attribute("class", highway)
			if highway == "motorway" or highway == "trunk" then MinZoom(4)
			elseif highway == "primary" then MinZoom(7)
			elseif highway == "secondary" then MinZoom(9)
			elseif highway == "tertiary" then MinZoom(10)
			else MinZoom(12) end
		end
		
		-- Road names
		if name ~= "" then
			Layer("transportation_name", false)
			Attribute("name", name)
			Attribute("name:latin", Find("name:en") ~= "" and Find("name:en") or name)
			Attribute("ref", Find("ref"))
			Attribute("class", highway)
			MinZoom(10)
		end
	end
	
	-- Water
	if water ~= "" or natural == "water" or waterway == "riverbank" then
		Layer("water", true)
		Attribute("class", water ~= "" and water or "lake")
		MinZoom(4)
	end
	
	if waterway == "river" or waterway == "canal" or waterway == "stream" then
		Layer("waterway", false)
		Attribute("class", waterway)
		if name ~= "" then Attribute("name", name) end
		MinZoom(8)
	end
	
	-- Landcover
	if natural == "wood" or landuse == "forest" then
		Layer("landcover", true)
		Attribute("class", "wood")
		MinZoom(6)
	elseif natural == "grassland" or landuse == "grass" or landuse == "meadow" then
		Layer("landcover", true)
		Attribute("class", "grass")
		MinZoom(10)
	end
	
	-- Landuse
	if landuse == "residential" or landuse == "industrial" or landuse == "commercial" or landuse == "retail" then
		Layer("landuse", true)
		Attribute("class", landuse)
		MinZoom(10)
	end
	
	-- Parks
	if leisure == "park" or leisure == "garden" then
		Layer("park", true)
		Attribute("class", leisure)
		if name ~= "" then Attribute("name", name) end
		MinZoom(10)
	end
	
	-- Boundaries
	if boundary == "administrative" then
		local admin_level = Find("admin_level")
		if admin_level == "2" or admin_level == "4" or admin_level == "6" then
			Layer("boundary", false)
			AttributeNumeric("admin_level", tonumber(admin_level))
			MinZoom(0)
		end
	end
	
	-- Housenumber from ways (polygons)
	local housenumber = Find("addr:housenumber")
	if housenumber ~= "" and building == "" then
		LayerAsCentroid("housenumber")
		Attribute("housenumber", housenumber)
		local street = Find("addr:street")
		if street ~= "" then Attribute("addr:street", street) end
	end
end

function relation_scan_function()
	if Find("type") == "multipolygon" or Find("type") == "boundary" then
		Accept()
	end
end

function relation_function()
	local reltype = Find("type")
	if reltype == "multipolygon" or reltype == "boundary" then
		way_function()
	end
end
