#!/usr/bin/env ruby
require 'yaml'
require 'thread'
require 'colorize'
require 'logger'
require_relative 'strategy'


$log = Logger.new($stdout)
$log.formatter = proc do |severity, datetime, progname, msg|
     "#{msg}\n"
end

$debug = ARGV.delete('-d')
$pause = ARGV.delete('-p')

$log.level = Logger::INFO
$log.level = Logger::DEBUG if $debug

class Marble
  attr_reader :owner
  def initialize(owner)
    @owner = owner
  end
end

class Board

  attr_reader :holes     # hash, keys are integers, yolo, bench_<leg>_<i>, endzone_<leg>_<i>

  COLORS = %w[red green light_blue yellow magenta white light_black].map(&:to_sym)

  def initialize(num_legs = 6, leg_height = 5, whos_playing = nil)
    @holes = {}
    @num_legs = num_legs
    @leg_height = leg_height
    populate_start(whos_playing || (0..@num_legs-1).to_a)
  end

  def num_normal_holes
    leg_perimeter * @num_legs
  end

  def leg_perimeter
    @leg_height * 3 - 3
  end

  def marbles_per_player
    @leg_height - 1
  end

  def yolo_entry?(hole_key)
    (hole_key.is_a? Fixnum) && (yolo_exits.include? hole_key)
  end

  def bench_exit?(hole_key)
    (hole_key.is_a? Fixnum) && (bench_exits.include? hole_key)
  end

  def endzone_entries
    (0..@num_legs).to_a.map do |i|
      (i * leg_perimeter - (@leg_height / 2).to_i) % num_normal_holes
    end.uniq
  end

  def endzone_entry?(hole)
    (hole.is_a? Fixnum) && (endzone_entries.include? hole)
  end

  def endzone_entry_for(player)
    (player * leg_perimeter - (@leg_height / 2)) % num_normal_holes
  end

  # Yolo exit closest to your endzone without passing it
  def last_yolo_exit_for(player)
    (player * leg_perimeter - (@leg_height * 2 - 2)) % num_normal_holes
  end

  # Takes in a hole that must be an endzone entry point.
  # returns nil if it is not one.
  def endzone_owner(hole)
    endzone_entries.index(hole)
  end

  def bench_owner(hole)
    @holes.keys.select { |k| k.to_s =~ /bench/ }.index(hole)
  end

  def yolo_exits
    (0..@num_legs).to_a.map do |i|
      (i * leg_perimeter + (@leg_height - 1)) % num_normal_holes
    end.uniq
  end

  def bench_exits
    (0..@num_legs).to_a.map do |i|
      (i * leg_perimeter) % num_normal_holes
    end.uniq
  end

  def holes_for_player(player)
    @holes.keys.select { |h| @holes[h] && @holes[h].owner == player }
  end

  # pass in an array of which players are playing
  def populate_start(roster)
    $log.debug "Initializing board for players #{roster.inspect}"
    roster.each do |player_num|
      marbles_per_player.times do |i|
        @holes["bench_#{player_num}_#{i}"] = Marble.new(player_num)
      end
    end
  end

  def winners
    out = []
    @num_legs.times do |player|
      out << player if (0..marbles_per_player - 1).inject(true) do |won, marble|
        won && !!@holes["endzone_#{player}_#{marble}"]
      end
    end
    out
  end

  # physical reachability for single hole-to-hole moves;
  # does not take into account whether or not another marble is already there,
  # or other rules, except that only endzone owners can reach their endzones
  def reachable_holes(start, player, roll)
    dests = []
    dests << 'yolo' if yolo_entry?(start)
    valid_endzone_entry = false
    if endzone_entry?(start) && endzone_owner(start) == player
      valid_endzone_entry = true
      dests << "endzone_#{player}_0"
    elsif start.to_s =~ /bench/
      leg = start.split('_')[1].to_i
      dests << leg_perimeter * leg
    elsif start.to_s == 'yolo' && roll == 1
      dests << yolo_exits
    elsif start.to_s =~ /endzone/
      player = start.split('_')[1].to_i
      pos = start.split('_')[2].to_i
      if pos + 1 < marbles_per_player
        dests << "endzone_#{player}_#{pos + 1}"
      end
    end
    # "Normal" case; it's a normal hole and not this player's death hole
    if (start.is_a? Fixnum) && !valid_endzone_entry
      dests << [(start + 1) % num_normal_holes]
    end
    dests.flatten.uniq
  end

  def remote_reachable_holes(start, roll, player)
    return start if roll == 0
    reachable = []

    # This first case might not be necessary
    if roll == 1 || ((start.to_s =~ /bench/))
      return reachable_holes(start, player, roll)
    else
      index = 0
      reachable = start
      while index < roll
        reachable = reachable_holes(reachable, player, roll)

        # Only allow yolo to be returned if this is the last step
        if index < roll - 1
          reachable.delete('yolo')
          reachable = reachable.first
        end

        index += 1
      end
    end
    [reachable].flatten.uniq
  end

  # Returns the holes on the path to finish from start
  # Uses depth-first search
  # Includes start and finish
  def path(start, finish, player, roll, progress = 0, prev = nil)

    # Special case: start == finish
    return [start] if start == finish
    return nil if progress > 6
    return nil if start == 'yolo' && roll != 1
    path = []

    # Special case: start is next to finish
    if reachable_holes(start, player, roll).include? finish
      return [start, finish]

    # Normal cases
    else
      reachable_holes(start, player, roll).each do |h|

        next_path = path(h, finish, player, roll, progress + 1, [start, prev].compact.flatten)
        if next_path
          return [start, next_path].flatten
        else
          next
        end
      end
    end
    return nil
  end

  def distance(start, finish, player, roll)
    path(start, finish, player).length - 1
  end

  def obstructed_path?(start, finish, player, roll)
    if @holes[start].nil?
      fail " START IS NIL"
    end
    thepath = path(start, finish, player, roll)[1..-1]
    thepath.each do |hole|
      if @holes[hole] && (@holes[hole].owner == @holes[start].owner)
        return true
      end
    end
    #print " false\n"
    return false
  end

  def to_s
    lines = ['']
    # Yolo
    yolo = '!'
    if @holes['yolo']
      yolo = yolo.colorize(color: :black, background: COLORS[@holes['yolo'].owner])
    end
    lines << '  ' * (num_normal_holes / 2) + yolo + "\n"

    # Benches and end-zones
    bench_lines = []
    endzone_lines = []
    marbles_per_player.times do |row|
      bench_line = ''
      endzone_line = ''
      num_normal_holes.times do |col|
        if bench_exit?(col)
          char = 'b'
          owner = col / leg_perimeter
          if @holes["bench_#{owner}_#{row}"]
            char = char.colorize(color: :black, background: COLORS[owner])
          else
            char = char.colorize(color: COLORS[owner])
          end
          bench_line << char + ' '
        else
          bench_line << '  '
        end
        if endzone_entry?(col)
          owner = (col / leg_perimeter + 1) % @num_legs
          char = 'w'
          if @holes["endzone_#{owner}_#{row}"]
            char = char.colorize(color: :black, background: COLORS[owner])
          else
            char = char.colorize(color: COLORS[owner])
          end
          endzone_line << char + ' '
        else
          endzone_line << '  '
        end
      end
      bench_lines << bench_line
      endzone_lines << endzone_line
    end

    lines += endzone_lines.reverse

    # Normal holes
    normal_line = ''
    num_normal_holes.times do |i|
      if yolo_entry?(i)
        char = '^'
      elsif bench_exit?(i)
        char = 'o'
      elsif endzone_entry?(i)
        char = '='
      else
        char = '-'
      end
      if @holes[i]
        char = char.colorize(color: :black, background: COLORS[@holes[i].owner])
      end
      normal_line << char + ' '
    end

    ticks_line = ''
    num_normal_holes.times do |i|
      if i % 10 == 0
        char = i.to_s
      else
        char = ' '
      end
      if char.length == 1
        char += ' '
      end
      ticks_line << char
    end

    player_labels_line = ''
    num_normal_holes.times do |i|
      if i % leg_perimeter == 0
        player = i / leg_perimeter
        char = "p#{player}".colorize(color: COLORS[player])
      else
        char = '  '
      end
      player_labels_line << char
    end

    lines << normal_line
    lines << ticks_line
    lines += bench_lines
    lines << player_labels_line
    return lines.join("\n") + "\n"
  end
end

class Game

  attr_reader :turn, :board, :active_player, :num_players

  def initialize(num_players = 6, board = nil)
    if board
      @board = board
    else
      @board = Board.new(num_players)
    end
    @turn = 0
    @num_players = num_players
    @active_player = Random.rand(num_players)
    $log.info "First player is #{@active_player}"
  end

  def roll_die
    return Random.rand(6) + 1
  end

  def winners
    @board.winners
  end

  def execute_move(start, finish)
    # If there's a marble at the destination, kill it
    if @board.holes[finish]
      killer = @board.holes[start].owner
      victim = @board.holes[finish].owner
      $log.debug "KILL #{killer} -> #{victim}'s marble at #{@board.holes[finish]}"
      fail "suicide!!" if killer == victim

      # Find a free bench spot for the killed marble
      cur_bench = @board.holes_for_player(victim).
        select { |h| (h.to_s =~ /bench/) }.
        map { |h| h.split('_')[2].to_i }
      empty = ([0,1,2,3] - cur_bench).first
      @board.holes["bench_#{victim}_#{empty}"] = @board.holes[finish].dup
    end

    @board.holes[finish] = @board.holes[start].dup
    @board.holes[start] = nil
  end

  def run(&blk)
    done = false
    @active_player = 0

    until done
      roll = roll_die

      # Log stuff
      $log.debug ''
      $log.debug "Turn #{@turn}".
        colorize(color: Board::COLORS[@active_player])
      $log.debug "player: #{@active_player}, roll: #{roll}".
        colorize(color: Board::COLORS[@active_player])
      $log.debug "Marbles for player #{@active_player}: " +
        "#{@board.holes_for_player(@active_player).inspect}"

      # Should never happen...
      if @board.holes_for_player(@active_player).count < @board.marbles_per_player
        fail "lost a marble?"
      end

      moves = available_moves(@active_player, roll)

      $log.debug "moves for player #{@active_player}: #{moves.inspect}"

      start = finish = nil
      if block_given?
        start, finish = yield(@active_player, moves, roll, @board)
      end

      $log.debug "Player #{@active_player} is choosing #{[start, finish].inspect}"

      if start && finish
        # There must be a marble at the starting position
        unless @board.holes[start]
          fail "No marble at #{start}"
        end

        # Player must own marble in starting position
        unless @board.holes[start].owner == @active_player
          fail "Player #{@active_player} cannot move player #{@board.holes[start].owner}'s marble"
        end

        # The destination must be physically reachable
        unless @board.remote_reachable_holes(start, roll, @active_player).include? finish
          fail "#{start} is not reachable from #{finish}"
        end

        # The path must not be obstructed
        if @board.obstructed_path?(start, finish, @active_player, roll)
          fail "path from #{start} to #{finish} is obstructed: #{@board.to_s}"
        end

        # Finally, if it's totally valid, execute the move
        execute_move(start, finish)

        # Is there a winner yet?  # TODO
        if @board.winners.count > 0
          done = true
          $log.info "WINNER: player #{@board.winners.first}, after #{@turn} turns"
          $log.info board
        end
      end

      $log.debug @board
      gets if $pause

      @active_player = ((@active_player + 1) % @num_players) unless roll == 6
      @turn += 1
    end
  end

  # Returns [ [start, finish], [start, finish] ]
  def available_moves(player, roll)
    moves = []

    # Start with all reachable holes given the die roll
    @board.holes_for_player(player).each do |hole|
      reachable = @board.remote_reachable_holes(hole, roll, player)
      reachable.each do |finish|
        moves << [hole, finish]
      end
    end

    #puts "pre-rejection moves are #{moves.inspect}"
    to_reject = []

    # Reject moves that don't comply with the rules
    moves.count.times do |i|
      start = moves[i][0]
      finish = moves[i][1]

      # The path must not be obstructed
      if @board.obstructed_path?(start, finish, player, roll)
        $log.debug "path between #{start} and #{finish} obstructed"
        to_reject << i
      end

      # Reject moves that start at the bench unless roll is 1 or 6
      if (start.to_s =~ /bench/) && !([1,6].include? roll)
        $log.debug "cannot leave #{start} unless roll is 1 or 6"
        to_reject << i
      end

      # Can only leave yolo with a 1 #TODO probably not needed
      to_reject << i if (start =~ /yolo/ && !(roll == 1))
    end

    #puts "rejecting #{to_reject.uniq}"
    to_reject.uniq.reverse.each { |i| moves.delete_at(i) }

    moves
  end
end

if __FILE__ == $0
  include Strategy

  game = Game.new(6)
  game.run do |player, moves, roll, board|

    # Apply these strategies in order (i.e., last resort is random)
    choice ||= obvious_move_choice(player, moves, board)
    choice ||= smart_leave_yolo(player, moves, board)
    choice ||= enter_endzone(player, moves, board)
    choice ||= kill(player, moves, board)
    choice ||= enter_yolo(player, moves, board)
    choice ||= scoot_endzone(player, moves, board)
    choice ||= random(player, moves, board)
  end
  $log.info "done"
end
