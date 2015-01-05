#!/usr/bin/env ruby

require 'yaml'

require_relative 'wahoo_game'
require_relative 'strategy'

$log.level = Logger::WARN

include Strategy

NUM_LEGS = 6
NUM_PLAYERS = 6
LEG_HEIGHT = 5
NUM_GAMES = 100
NUM_SETS = 20


def build_strats(num_players)
  strat_methods = Strategy.public_instance_methods
  strat_methods.delete(:obvious_move_choice)
  strat_methods.delete(:random)

  player_strats = []
  num_players.times do |i|
    strat_priority = [:obvious_move_choice]
    strat_priority += strat_methods.shuffle
    strat_priority += [:random]
    player_strats << strat_priority
  end
  player_strats
end

def run_set(player_strats)
  report = []
  NUM_GAMES.times do |game_index|
    print '.' if $log.level == Logger::WARN

    game = Game.new(NUM_LEGS)
    game.run do |player, moves, roll, board|
      choice = nil
      player_strats[player].each do |strat_method|
        choice ||= send(strat_method, player, moves, board)
      end
      choice
    end
    report[game_index] = {
      winner: game.winners.first,
      turns: game.turn
    }
  end
  print "\n" if $log.level == Logger::WARN
  report
end

puts "#{NUM_SETS} sets of #{NUM_GAMES} games..."
best_strat = nil
NUM_SETS.times do |i|

  player_strats = build_strats(NUM_PLAYERS)
  if best_strat
    player_strats[0] = best_strat
    puts "best strat: #{best_strat.join(' ')}"
    puts win_hist.sort.join(' ')
  end

  print "Set #{i}" if $log.level == Logger::WARN
  report = run_set(player_strats)

  win_hist = [0] * NUM_PLAYERS
  report.each { |game| win_hist[game[:winner]] += 1 }
  best_player = win_hist.each_with_index.max[1]
  best_strat = player_strats[best_player]
end

puts "Best strategy: #{best_strat.join(' ')}"
