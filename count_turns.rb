#!/usr/bin/env ruby

require 'yaml'

require_relative 'wahoo_game'
require_relative 'strategy'

$log.level = Logger::ERROR

include Strategy

LEG_HEIGHTS = [3,4,5]
LEG_COUNTS = [3,4,5,6,7]
NUM_GAMES = 100

def run_set(num_legs, leg_height)
  report = []
  NUM_GAMES.times do |game_index|
    print '.' if $log.level == Logger::WARN

    game = Game.new(num_legs, Board.new(num_legs, leg_height))
    #game = Game.new(num_legs)
    game.run do |player, moves, roll, board|
      choice = nil
      choice ||= obvious_move_choice(player, moves, board)
      choice ||= smart_leave_yolo(player, moves, board)
      choice ||= enter_endzone(player, moves, board)
      choice ||= kill(player, moves, board)
      choice ||= enter_yolo(player, moves, board)
      choice ||= scoot_endzone(player, moves, board)
      choice ||= random(player, moves, board)
      choice
    end
    report << game.turn
  end
  print "\n" if $log.level == Logger::WARN
  report.reduce(:+) / report.count
end

puts "Testing leg counts #{LEG_COUNTS}; sets of #{NUM_GAMES} games..."
best_strat = nil
LEG_COUNTS.each do |num_legs|
  LEG_HEIGHTS.each do |leg_height|
    print "#{num_legs} legs, leg length #{leg_height}: "
    puts "#{run_set(num_legs, leg_height)} turns"
  end
end
