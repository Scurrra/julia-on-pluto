### A Pluto.jl notebook ###
# v0.20.3

using Markdown
using InteractiveUtils

# ╔═╡ ac9d623a-ba18-11ef-1899-fd42d0defcff
# ╠═╡ show_logs = false
begin
	using Agents, Agents.Graphs
	using Plots, GraphRecipes
	using Random, StatsBase
	using DataFrames, OrderedCollections

	using PlutoUI;
	TableOfContents()
end

# ╔═╡ 577de7b6-8adf-4df8-a9e2-27ae4e514083
md"""
# [The True One](https://www.youtube.com/watch?v=hCXVd_tQ8yc)
"""

# ╔═╡ 880a9c16-09b8-4610-97fe-96faf78877ae
html"""
<div style="padding:56.25% 0 0 0;position:relative;">
	<iframe src="https://www.youtube.com/embed/hCXVd_tQ8yc?si=D4NaucIWEy-Gsyz9" style="position:absolute;top:0;left:0;width:100%;height:100%;" frameborder="0" allow="autoplay; fullscreen" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
</div>
"""

# ╔═╡ fa284633-b9bb-4251-97b8-dd4add9ec385
md"""
## Agent a.k.a. Drinking Citizen
"""

# ╔═╡ 30e06003-c86f-46dc-bada-048aefbf76ad
begin
	@agent struct DrinkingCitizen(GraphAgent)
		team::Int
		beer_drunk::Rational
		beer_in_hands::Rational # between 0 and 3
		bac_pm::Float64

		sex::Symbol # :male or :female
		weight::Int # in kilos
	end
	
	bac_pm(drunkard::DrinkingCitizen; ac=5.0) = 
		let volume = 0.5*drunkard.beer_drunk*ac*0.789,
			r = drunkard.sex==:male ? 0.68 : 0.55;
		return volume / (drunkard.weight * r)
	end
	
	bac_pm!(drunkard::DrinkingCitizen; ac=5.0) = 
		let volume = 0.5*drunkard.beer_drunk*ac*0.789,
			r = drunkard.sex==:male ? 0.68 : 0.55;
		drunkard.bac_pm = volume / (drunkard.weight * r)
	end
end

# ╔═╡ 8f5bf262-418e-440a-b58e-f1a52044dbfe
available_moves(model) = 
	let positions = sort([a.id=>a.pos for a in allagents(model)]; by=x->x.second); 
	push!(positions, positions[1].first => positions[1].second+model.field_size)
	return Dict(
		positions[i].first => positions[i+1].second-positions[i].second-1
		for i in 1:length(positions)-1
	)
end

# ╔═╡ 02b15c0c-6761-4372-a6eb-2392e3e50230
md"""
## Single model step
"""

# ╔═╡ 21544816-fde2-4d35-9f8e-dc2e64e64d59
function model_step!(model)
	rng = abmrng(model)
	
	# reanimate dead agents
	for a in model.agents_in_lava
		if a.beer_in_hands < 1
			a.beer_drunk += 1 + a.beer_in_hands
		elseif a.beer_in_hands > 3
			a.beer_drunk += a.beer_in_hands
		end
		a.beer_in_hands = 1
		bac_pm!(a)
		add_agent!(
			a, rand(rng, findall(isempty, abmspace(model).stored_ids)),
			model
		)
	end
	empty!(model.agents_in_lava)
	
	current_agent_id = model.current_player
	current_agent = model[current_agent_id]
	available_moves_per_agent = available_moves(model)
	# select the game
	move = rand(rng, 1:3)
	if model.use_teams
		teammates = model.teams[current_agent.team] |> copy
		deleteat!(teammates, findall(==(current_agent_id), teammates))
		# @show current_agent => teammates

		moves = [available_moves_per_agent[t] for t in teammates]
		moves[moves .> 3] .= 3
		move = sample(rng, moves, Weights(moves))
		move = move == 0 ? rand(rng, 1:3) : move
	end

	# select the next player
	probs = sort([
		a.id => a.id == current_agent_id || a.bac_pm > 3 ? 0 :
			available_moves_per_agent[a.id] < move ? 0 :
				1 / model.scale_function(a.bac_pm)
		for a in allagents(model)
	]; by=a->a.first) .|> last |> Weights
	id = sample(rng, 1:length(probs), probs)
	while available_moves_per_agent[id] < move 
		id = sample(rng, 1:length(probs), probs)
	end
	agent = model[id]

	model.current_move = move
	
	# move the player
	for _ in 1:move
		# whether player falls
		if rand(rng) > 1 / model.scale_function(agent.bac_pm)
			push!(model.agents_in_lava, agent)
			remove_agent!(agent, model)
			println("Step $(abmtime(model)): Fallen player: $(agent.id)")
			agent = current_agent
			break
		end

		# move player one step
		move_agent!(agent, (agent.pos % model.field_size) + 1, model)

		# check if player should grab one more pawn
		if agent.pos % div(model.field_size, model.num_of_sections) == 0
			if model.num_of_pawns == 0
				model.num_of_pawns -= 1
				model.current_player = agent.id
				println("Step $(abmtime(model)): Agent $(agent.id) wins!")
				return "Agent $(agent.id) wins!"
			end
			
			model.num_of_pawns -= 1
			agent.beer_in_hands += 1
			if agent.beer_in_hands > 3
				push!(model.agents_in_lava, agent)
				remove_agent!(agent, model)
				println("Step $(abmtime(model)): Too many beers: $(agent.id)")
				agent = current_agent
				break
			end
		end
	end

	# every citizen should drink
	for a in allagents(model)
		beer = min(
			ceil(a.beer_in_hands)*(a.sex==:male ? 21//500 : 14//500), 
			a.beer_in_hands
		)
		a.beer_in_hands -= beer
		a.beer_drunk += beer
		bac_pm!(a)
		if a.beer_in_hands == 0
			push!(model.agents_in_lava, a)
			remove_agent!(a, model)
			println("Step $(abmtime(model)): Too few beers: $(a.id)")
		end
	end

	# rewrite player (if it didn't fail)
	if agent in model.agents_in_lava
		available_players = 1:length(probs) |> collect
		deleteat!(available_players, sort(map(a->a.id, model.agents_in_lava)))
		model.current_player = rand(rng, available_players)	
	else
		model.current_player = agent.id
	end
end

# ╔═╡ 3bb962a9-0e26-401d-9426-a314230687e6
md"""
## Model setup
"""

# ╔═╡ a35a6247-8215-4b12-a3cb-8f60e524b083
function model_initiation(;
	field_size::Int=20,
	num_of_sections=4,
	num_of_players::Int=8,
	sex_n_weight::Vector{Pair{Symbol,Int}}=Pair{Symbol,Int}[],
	beer_drunk::Vector=[],
	use_teams::Bool=true,
	num_of_pawns::Int=40,
	seed=42,
	scale_function=identity
)
	rng = Xoshiro(seed)
	properties = Dict{Symbol, Any}(
		:current_player => rand(rng, 1:num_of_players),
		:current_move => 0,
		:num_of_pawns => num_of_pawns,
		:use_teams => use_teams,
		:field_size => field_size,
		:num_of_sections => num_of_sections,
		:agents_in_lava => DrinkingCitizen[],
		:scale_function => scale_function
	)
	
	beer_drunk = length(beer_drunk)==num_of_players ? beer_drunk : 
		rand(rng, 1:5, num_of_players)
	@assert num_of_players == length(sex_n_weight) == length(beer_drunk) "Please, set num of beer drunked, sex and weight for each player"
	@assert num_of_players < field_size "Field is too small"
	@assert mod(field_size, num_of_sections) == 0 "Number of sections shold be a divisor of field size"

	teams = nothing
	if use_teams
		teams = rand(1:5, num_of_players)
		while true
			b = zeros(Int, 5)
			foreach(i->b[i]+=1, teams)
			allequal(filter(>(0), b)) && break
			teams = rand(1:5, num_of_players)
		end

		properties[:teams] = Dict(map(
			t->t=>findall(==(t), teams),
			unique(teams)
		))
	end

	indx = rand(1:field_size, num_of_players)
	while true
		b = zeros(Int, field_size)
		foreach(i->b[i]+=1, indx)
		length(filter(>(0), b)) == num_of_players && break
		indx = rand(1:field_size, num_of_players)
	end
	
	space = GraphSpace(cycle_digraph(field_size))
	model = StandardABM(
		DrinkingCitizen, space;
		model_step!, properties, rng
	)

	if use_teams
		for i in 1:num_of_players
			a = add_agent!(indx[i], model, 
				teams[i], beer_drunk[i], 1, 0,
				sex_n_weight[i]... 
			)
			bac_pm!(a)
		end
	else
		for i in 1:num_of_players
			a = add_agent!(indx[i], model, 
				0, beer_drunk[i], 1, 0,
				sex_n_weight[i]... 
			)
			bac_pm!(a)
		end
	end

	return model
end

# ╔═╡ 115058c7-b9b1-450b-b2cb-1db901cc135b
md"""
## Model init
"""

# ╔═╡ f8f5be0f-6c6d-40ed-9bb4-956da3edfc39
model = model_initiation(;
	sex_n_weight=rand((:male, :female), 8) .=> rand(50:80, 8),
	beer_drunk=rand(1:10, 8),
#	scale_function=exp
)

# ╔═╡ 256592c5-b811-4e8e-b9d2-e9b62c9f563e
model.teams

# ╔═╡ 5324c743-7d35-48d6-a2fa-98bcb5eae0ba
model |> allagents

# ╔═╡ 53be55a4-660f-4768-8937-0ab771481062
md"""
## Run simulation
"""

# ╔═╡ 3d17bc9a-5d78-464d-9805-dbb3a9241b7d
begin
	data = OrderedDict(
		:step => [],
		:current_player => [],
		:current_player_bac => [],
		:current_move => [],
		:current_agent => [],
		:current_agent_bac => [],
		:num_of_pawns => [],
		:agents_in_lava => []
	)
	
	while model.num_of_pawns >= 0
		push!(data[:current_player], model.current_player)
		push!(data[:current_player_bac], model[model.current_player].bac_pm)
		
		Agents.step!(model, 1)

		push!(data[:step], abmtime(model))
		push!(data[:current_move], model.current_move)
		push!(data[:current_agent], model.current_player)
		try
			push!(data[:current_agent_bac], model[model.current_player].bac_pm)
		catch
			agent = filter(a->a.id==model.current_player, model.agents_in_lava)[1]
			push!(data[:current_agent_bac], agent.bac_pm)
		end
		push!(data[:num_of_pawns], model.num_of_pawns)
		push!(data[:agents_in_lava], map(m->(m.id, m.bac_pm), model.agents_in_lava))
	end

	DataFrame(data)
end

# ╔═╡ 1e541c62-1f26-4c73-b5ea-c12b32538ea8
model |> allagents

# ╔═╡ Cell order:
# ╟─ac9d623a-ba18-11ef-1899-fd42d0defcff
# ╟─577de7b6-8adf-4df8-a9e2-27ae4e514083
# ╟─880a9c16-09b8-4610-97fe-96faf78877ae
# ╟─fa284633-b9bb-4251-97b8-dd4add9ec385
# ╠═30e06003-c86f-46dc-bada-048aefbf76ad
# ╠═8f5bf262-418e-440a-b58e-f1a52044dbfe
# ╟─02b15c0c-6761-4372-a6eb-2392e3e50230
# ╠═21544816-fde2-4d35-9f8e-dc2e64e64d59
# ╟─3bb962a9-0e26-401d-9426-a314230687e6
# ╠═a35a6247-8215-4b12-a3cb-8f60e524b083
# ╟─115058c7-b9b1-450b-b2cb-1db901cc135b
# ╠═f8f5be0f-6c6d-40ed-9bb4-956da3edfc39
# ╠═256592c5-b811-4e8e-b9d2-e9b62c9f563e
# ╠═5324c743-7d35-48d6-a2fa-98bcb5eae0ba
# ╟─53be55a4-660f-4768-8937-0ab771481062
# ╠═3d17bc9a-5d78-464d-9805-dbb3a9241b7d
# ╠═1e541c62-1f26-4c73-b5ea-c12b32538ea8
