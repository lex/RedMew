-- Tests for High Stakes' cards: reading poker hands, ordering them, and the dealer's rigged hands.
-- Discovered whenever cards.lua is loaded (the High Stakes scenario).

local Declare = require 'utils.test.declare'
local Assert = require 'utils.test.assert'
local Cards = require 'map_gen.maps.high_stakes.cards'

local types = Cards.hand_types
local C = Cards.card
local s = Cards.suits

-- a card from its rank and the first letter of its suit: c(13, 'f') is the king of fire
local function c(rank, suit)
    local suits = { c = s.crosshair, l = s.lightning, f = s.fire, e = s.explosion }
    return C(rank, suits[suit])
end

Declare.module({ 'map_gen', 'High Stakes', 'cards' }, function()
    Declare.test('a card keeps its rank and suit', function()
        for rank = 2, Cards.ace do
            for suit = 1, 4 do
                -- Act
                local card = C(rank, suit)

                -- Assert
                Assert.equal(rank, Cards.rank(card), 'rank of ' .. card)
                Assert.equal(suit, Cards.suit(card), 'suit of ' .. card)
            end
        end
    end)

    local hands = {
        { name = 'high card', cards = { c(2, 'c'), c(9, 'l'), c(13, 'f'), c(5, 'e'), c(7, 'c') }, type = types.high_card, rank = 13, used = { 3 } },
        { name = 'pair', cards = { c(9, 'c'), c(4, 'l'), c(9, 'f'), c(12, 'e'), c(7, 'c') }, type = types.pair, rank = 9, used = { 1, 3 } },
        { name = 'two pair', cards = { c(9, 'c'), c(4, 'l'), c(9, 'f'), c(4, 'e'), c(7, 'c') }, type = types.two_pair, rank = 9, used = { 1, 2, 3, 4 } },
        { name = 'three of a kind', cards = { c(6, 'c'), c(6, 'l'), c(9, 'f'), c(6, 'e'), c(7, 'c') }, type = types.three_of_a_kind, rank = 6, used = { 1, 2, 4 } },
        { name = 'straight with the ace low', cards = { c(14, 'c'), c(2, 'l'), c(3, 'f'), c(4, 'e'), c(5, 'c') }, type = types.straight, rank = 5, used = { 1, 2, 3, 4, 5 } },
        { name = 'straight', cards = { c(6, 'c'), c(8, 'l'), c(9, 'f'), c(10, 'e'), c(7, 'c') }, type = types.straight, rank = 10, used = { 1, 2, 3, 4, 5 } },
        { name = 'straight with the ace high', cards = { c(14, 'c'), c(13, 'l'), c(12, 'f'), c(11, 'e'), c(10, 'c') }, type = types.straight, rank = 14, used = { 1, 2, 3, 4, 5 } },
        { name = 'flush', cards = { c(2, 'f'), c(9, 'f'), c(13, 'f'), c(5, 'f'), c(7, 'f') }, type = types.flush, rank = 13, used = { 1, 2, 3, 4, 5 } },
        { name = 'full house', cards = { c(3, 'c'), c(11, 'l'), c(3, 'f'), c(11, 'e'), c(3, 'l') }, type = types.full_house, rank = 3, used = { 1, 2, 3, 4, 5 } },
        { name = 'four of a kind', cards = { c(8, 'c'), c(8, 'l'), c(8, 'f'), c(2, 'e'), c(8, 'e') }, type = types.four_of_a_kind, rank = 8, used = { 1, 2, 3, 5 } },
        { name = 'straight flush', cards = { c(5, 'e'), c(6, 'e'), c(7, 'e'), c(8, 'e'), c(9, 'e') }, type = types.straight_flush, rank = 9, used = { 1, 2, 3, 4, 5 } }
    }

    for _, case in ipairs(hands) do
        Declare.test('reads a ' .. case.name, function()
            -- Act
            local hand = Cards.evaluate(case.cards)

            -- Assert
            Assert.equal(case.type, hand.type, 'hand type')
            Assert.equal(case.rank, hand.rank, 'hand rank')
            Assert.table_equal(case.used, hand.used, 'cards that make the hand')
        end)
    end

    Declare.test('a wrap-around run is not a straight', function()
        -- Arrange: Q K A 2 3
        local cards = { c(12, 'c'), c(13, 'l'), c(14, 'f'), c(2, 'e'), c(3, 'c') }

        -- Act
        local hand = Cards.evaluate(cards)

        -- Assert
        Assert.equal(types.high_card, hand.type, 'hand type')
    end)

    Declare.test('better hands score higher', function()
        -- Act
        local scores = {}
        for i, case in ipairs(hands) do
            scores[i] = Cards.score(Cards.evaluate(case.cards))
        end

        -- Assert: the cases are listed worst to best
        for i = 2, #scores do
            Assert.is_true(scores[i] > scores[i - 1], hands[i].name .. ' should beat ' .. hands[i - 1].name)
        end
    end)

    Declare.test('a new deck holds every card once', function()
        -- Arrange
        local random = game.create_random_generator(1001)

        -- Act
        local deck = Cards.new_deck(function(m, n)
            return random(m, n)
        end)

        -- Assert
        local seen = {}
        for _, card in pairs(deck) do
            Assert.is_true(not seen[card], 'card ' .. card .. ' twice')
            seen[card] = true
        end
        Assert.equal(52, table_size(seen), 'cards in the deck')
    end)

    Declare.test('the dealer never rigs a hand without a tip', function()
        -- Arrange
        local random = game.create_random_generator(1002)

        for _ = 1, 100 do
            -- Act
            local rigged = Cards.rigged_hand_type(0, function(m, n)
                return random(m, n)
            end)

            -- Assert
            Assert.is_nil(rigged, 'rigged hand with no tips')
        end
    end)

    Declare.test('nine tips always rig four of a kind or better', function()
        -- Arrange
        local random = game.create_random_generator(1003)

        for _ = 1, 200 do
            -- Act
            local rigged = Cards.rigged_hand_type(Cards.max_tips, function(m, n)
                return random(m, n)
            end)

            -- Assert
            Assert.is_true(rigged ~= nil and rigged >= types.four_of_a_kind, 'nine tips rigged ' .. tostring(rigged))
        end
    end)

    for hand_type = types.pair, types.straight_flush do
        local name = Cards.hand_type_names[hand_type]
        Declare.test('a rigged ' .. name .. ' holds at least a ' .. name, function()
            -- Arrange
            local random = game.create_random_generator(2000 + hand_type)
            local function r(m, n)
                return random(m, n)
            end

            for _ = 1, 50 do
                local deck = Cards.new_deck(r)

                -- Act
                local cards = Cards.deal_rigged(deck, hand_type, r)

                -- Assert
                local hand = Cards.evaluate(cards)
                Assert.equal(5, #cards, 'cards dealt')
                Assert.equal(47, #deck, 'cards left in the deck')
                Assert.is_true(hand.type >= hand_type, 'rigged ' .. name .. ' came out as ' .. Cards.hand_type_names[hand.type])
            end
        end)
    end
end)
