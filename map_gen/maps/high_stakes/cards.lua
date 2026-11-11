-- Cards, decks and poker hands. Pure logic: no game state, so it can be tested on its own.
--
-- A card is a number from 1 to 52: (rank - 2) * 4 + suit, with ranks 2 to 14 (14 is the ace)
-- and suits 1 to 4. The suits are Factorio's signals rather than the usual four: the
-- crosshair, lightning, fire and explosion, each a tower's way of attacking (see towers.lua).

local floor = math.floor
local sort = table.sort

local Public = {}

Public.suits = {
    crosshair = 1,
    lightning = 2,
    fire = 3,
    explosion = 4
}

Public.suit_names = { 'crosshair', 'lightning', 'fire', 'explosion' }
Public.suit_signals = { 'signal-damage', 'signal-lightning', 'signal-fire', 'signal-explosion' }

Public.rank_symbols = { [2] = '2', [3] = '3', [4] = '4', [5] = '5', [6] = '6', [7] = '7', [8] = '8', [9] = '9', [10] = '10', [11] = 'J', [12] = 'Q', [13] = 'K', [14] = 'A' }

Public.ace = 14

-- From worst to best: the order decides who wins a round.
Public.hand_types = {
    high_card = 0,
    pair = 1,
    two_pair = 2,
    three_of_a_kind = 3,
    straight = 4,
    flush = 5,
    full_house = 6,
    four_of_a_kind = 7,
    straight_flush = 8
}

Public.hand_type_names = { [0] = 'high_card', 'pair', 'two_pair', 'three_of_a_kind', 'straight', 'flush', 'full_house', 'four_of_a_kind', 'straight_flush' }

function Public.card(rank, suit)
    return (rank - 2) * 4 + suit
end

function Public.rank(card)
    return floor((card - 1) / 4) + 2
end

function Public.suit(card)
    return (card - 1) % 4 + 1
end

--- The card as rich text: its rank and its suit's signal, e.g. `K[virtual-signal=signal-fire]`.
function Public.text(card)
    return Public.rank_symbols[Public.rank(card)] .. '[virtual-signal=' .. Public.suit_signals[Public.suit(card)] .. ']'
end

--- A shuffled deck of 52 cards; draw from it with table.remove.
---@param random fun(m: integer, n: integer): integer
function Public.new_deck(random)
    local deck = {}
    for i = 1, 52 do
        deck[i] = i
    end
    for i = 52, 2, -1 do
        local j = random(1, i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    return deck
end

--- Removes these cards from the deck, so they can't be drawn again.
function Public.remove_from_deck(deck, cards)
    local taken = {}
    for _, card in pairs(cards) do
        taken[card] = true
    end
    for i = #deck, 1, -1 do
        if taken[deck[i]] then
            table.remove(deck, i)
        end
    end
end

-- The high card of a straight in these ranks (a set: rank -> true), or nil. The ace counts low
-- too: A 2 3 4 5 is a straight to the 5.
local function straight_high(ranks)
    for high = Public.ace, 6, -1 do
        local all = true
        for r = high - 4, high do
            if not ranks[r] then
                all = false
                break
            end
        end
        if all then
            return high
        end
    end
    if ranks[Public.ace] and ranks[2] and ranks[3] and ranks[4] and ranks[5] then
        return 5
    end
    return nil
end

--- The best poker hand in up to five cards.
---@param cards integer[]
---@return { type: integer, rank: integer, second: integer?, used: integer[], suit: integer? }
--- type is one of hand_types. rank is what the hand is "of": the pair's rank, the higher pair of
--- two, the three in a full house, a straight or flush's high card, or the high card itself.
--- second is the other pair or the full house's pair. used holds the indexes (into cards) of the
--- cards that make the hand. suit is the high card's or the flush's.
function Public.evaluate(cards)
    local count = #cards
    local by_rank = {}
    local ranks = {}
    local suits = {}
    for i = 1, count do
        local card = cards[i]
        local rank = Public.rank(card)
        local list = by_rank[rank]
        if not list then
            list = {}
            by_rank[rank] = list
        end
        list[#list + 1] = i
        ranks[rank] = true
        suits[Public.suit(card)] = (suits[Public.suit(card)] or 0) + 1
    end

    local all = {}
    for i = 1, count do
        all[i] = i
    end

    local flush_suit
    if count == 5 then
        for suit, n in pairs(suits) do
            if n == 5 then
                flush_suit = suit
            end
        end
    end
    local high = count == 5 and straight_high(ranks)

    if high and flush_suit then
        return { type = Public.hand_types.straight_flush, rank = high, used = all, suit = flush_suit }
    end

    -- groups of the same rank, biggest first, then highest
    local groups = {}
    for rank, list in pairs(by_rank) do
        groups[#groups + 1] = { rank = rank, indexes = list }
    end
    sort(groups, function(a, b)
        if #a.indexes ~= #b.indexes then
            return #a.indexes > #b.indexes
        end
        return a.rank > b.rank
    end)

    local first, second = groups[1], groups[2]
    if not first then
        return { type = Public.hand_types.high_card, rank = 0, used = {} }
    end

    if #first.indexes == 4 then
        return { type = Public.hand_types.four_of_a_kind, rank = first.rank, used = first.indexes }
    end

    if #first.indexes == 3 and second and #second.indexes >= 2 then
        local used = {}
        for _, i in pairs(first.indexes) do
            used[#used + 1] = i
        end
        for _, i in pairs(second.indexes) do
            used[#used + 1] = i
        end
        sort(used)
        return { type = Public.hand_types.full_house, rank = first.rank, second = second.rank, used = used }
    end

    if flush_suit then
        local top = 0
        for rank in pairs(ranks) do
            if rank > top then
                top = rank
            end
        end
        return { type = Public.hand_types.flush, rank = top, used = all, suit = flush_suit }
    end

    if high then
        return { type = Public.hand_types.straight, rank = high, used = all }
    end

    if #first.indexes == 3 then
        return { type = Public.hand_types.three_of_a_kind, rank = first.rank, used = first.indexes }
    end

    if #first.indexes == 2 and second and #second.indexes == 2 then
        local used = { first.indexes[1], first.indexes[2], second.indexes[1], second.indexes[2] }
        sort(used)
        return { type = Public.hand_types.two_pair, rank = first.rank, second = second.rank, used = used }
    end

    if #first.indexes == 2 then
        return { type = Public.hand_types.pair, rank = first.rank, used = first.indexes }
    end

    -- the high card: of several cards of the top rank, the first
    local index = first.indexes[1]
    return { type = Public.hand_types.high_card, rank = first.rank, used = { index }, suit = Public.suit(cards[index]) }
end

--- A number that orders hands: a better hand scores more, equal hands score the same.
function Public.score(hand)
    return hand.type * 100 + hand.rank
end

--- The cards of the hand, as rich text separated by spaces.
function Public.hand_text(cards, hand)
    local parts = {}
    for _, i in ipairs(hand.used) do
        parts[#parts + 1] = Public.text(cards[i])
    end
    return table.concat(parts, ' ')
end

-- Rigged hands, for players who tipped the dealer --------------------------------------------

-- How many tips a player can give: more are kept for the next hand.
Public.max_tips = 9

-- For each number of tips (rows, 1 to 9), the hand the dealer sets up (a hand type, 1 to 8) for
-- each of eight outcomes. The outcomes' odds are tip_odds, so the middle columns come up most:
-- a few tips mostly buy a pair or two, nine buy a straight flush or four of a kind.
Public.tip_table = {
    { 4, 3, 2, 1, 1, 2, 3, 4 },
    { 5, 4, 3, 2, 2, 3, 4, 5 },
    { 5, 5, 4, 3, 3, 4, 5, 5 },
    { 6, 5, 4, 3, 3, 4, 5, 6 },
    { 7, 6, 5, 4, 4, 5, 6, 7 },
    { 7, 7, 6, 5, 5, 6, 7, 7 },
    { 8, 7, 6, 5, 5, 6, 7, 8 },
    { 8, 8, 7, 6, 6, 7, 8, 8 },
    { 8, 8, 8, 7, 7, 8, 8, 8 }
}

-- The chance of each outcome, in percent.
Public.tip_odds = { 5, 10, 15, 20, 20, 15, 10, 5 }

--- Which hand type the dealer sets up for this many tips, or nil when the dealer doesn't. With
--- fewer than four tips the dealer may not bother: one tip works one time in four, two tips two
--- in four, three tips three in four.
---@param tips integer
---@param random fun(m: integer, n: integer): integer
---@return integer?
function Public.rigged_hand_type(tips, random)
    if tips < 1 then
        return nil
    end
    tips = math.min(tips, Public.max_tips)
    if tips < random(1, 4) then
        return nil
    end
    local roll = random(1, 100)
    local total = 0
    for column, odds in ipairs(Public.tip_odds) do
        total = total + odds
        if roll <= total then
            return Public.tip_table[tips][column]
        end
    end
    return Public.tip_table[tips][#Public.tip_odds]
end

local function take(deck, predicate)
    for i = #deck, 1, -1 do
        if predicate(deck[i]) then
            return table.remove(deck, i)
        end
    end
    return nil
end

local function take_rank(deck, rank)
    return take(deck, function(card)
        return Public.rank(card) == rank
    end)
end

local function take_card(deck, card)
    return take(deck, function(c)
        return c == card
    end)
end

-- n different ranks, in random order
local function distinct_ranks(n, random)
    local ranks = {}
    for r = 2, Public.ace do
        ranks[#ranks + 1] = r
    end
    for i = #ranks, 2, -1 do
        local j = random(1, i)
        ranks[i], ranks[j] = ranks[j], ranks[i]
    end
    local result = {}
    for i = 1, n do
        result[i] = ranks[i]
    end
    return result
end

--- Deals five cards from the deck that hold at least this hand type, in random order.
---@param deck integer[] drawn from
---@param hand_type integer 1 (pair) to 8 (straight flush)
---@param random fun(m: integer, n: integer): integer
---@return integer[]
function Public.deal_rigged(deck, hand_type, random)
    local types = Public.hand_types
    local cards = {}
    local function add(card)
        if card then
            cards[#cards + 1] = card
        end
    end

    if hand_type == types.straight or hand_type == types.straight_flush then
        local high = random(5, Public.ace)
        local suit = random(1, 4)
        for r = high - 4, high do
            local rank = r == 1 and Public.ace or r
            if hand_type == types.straight_flush then
                add(take_card(deck, Public.card(rank, suit)))
            else
                add(take_rank(deck, rank))
            end
        end
    elseif hand_type == types.flush then
        local suit = random(1, 4)
        for _, rank in pairs(distinct_ranks(5, random)) do
            add(take_card(deck, Public.card(rank, suit)))
        end
    else
        local sizes = ({
            [types.pair] = { 2 },
            [types.two_pair] = { 2, 2 },
            [types.three_of_a_kind] = { 3 },
            [types.full_house] = { 3, 2 },
            [types.four_of_a_kind] = { 4 }
        })[hand_type] or {}
        local ranks = distinct_ranks(#sizes, random)
        for i, size in ipairs(sizes) do
            for _ = 1, size do
                add(take_rank(deck, ranks[i]))
            end
        end
    end

    while #cards < 5 and #deck > 0 do
        cards[#cards + 1] = table.remove(deck)
    end
    for i = #cards, 2, -1 do
        local j = random(1, i)
        cards[i], cards[j] = cards[j], cards[i]
    end
    return cards
end

return Public
