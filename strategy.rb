module Strategy

  # Returns a single move if the choice is obvious
  def obvious_move_choice(player, moves, _board)
    # If all marbles are in the bench, just pick one
    if moves.inject(true) { |accum, move| accum && (move[0].to_s =~ /bench/) }
      return moves[0]
    end

    # If there is only one move, pick it
    if moves.count == 1
      return moves[0]
    end
    nil
  end

  # Go to the yolo exit closest to your endzone
  def smart_leave_yolo(player, moves, board)
    moves.find do |move|
      next unless move[0].to_s =~ /yolo/
      move[1] == board.last_yolo_exit_for(player)
    end
  end

  def enter_yolo(player, moves, _board)
    moves.find { |m| m[1].to_s =~ /yolo/ }
  end

  def enter_endzone(player, moves, _board)
    moves.find do |m|
      (m[1].to_s =~ /endzone/) && !(m[0].to_s =~ /endzone/)
    end
  end

  def leave_yolo(player, moves, _board)
  end

  def random(player, moves, _board)
    moves.sample
  end

  def leave_bench(player, moves, _board)
    moves.find { |m| m[0].to_s =~ /bench/ }
  end

  def kill(player, moves, board)
    moves.find { |m| board.holes[m[1]] }
  end

  def scoot_endzone(player, moves, _board)
    moves.find { |m| m[0].to_s =~ /endzone/ }
  end

end
