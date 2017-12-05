require 'slack'
require 'ribery'
require 'taunt'
require 'terminal-table'
require 'net/http'

class SlackBot
  #5947bd34-5c69-471e-91d4-f8db32673019
  def initialize(params)
    @user_id = params["user_id"]
    @text = params["text"] || ""
    @trigger_word = params["trigger_word"] || "frog"
    @slack_token = params["token"]

    Team.create_or_update(name: 'test', attack: 20, midfield: 29, defense: 20)
  end

  def answer
    return params if @slack_token != ENV["SLACK_WEBHOOK_TOKEN"]
    return "Bien tenté Jean-Mi" if @slack_token != ENV["SLACK_WEBHOOK_TOKEN"]

    data = @text.split

    begin
      return self.send("hear_#{data[1]}", *data[2..-1])
    rescue Exception => e
      puts e
      return help
    end
  end

  def help
    answer = "Command [option]\n"

    # hearers are methods starting with 'hear_'
    hearers = self.private_methods.select { |m| m.to_s.start_with? "hear_" }

    hearers.each do |hearer|
      parameters = self.method(hearer).parameters.map { |p| p.first == :opt ? "[#{p.second}]" : p.second }
      answer += "\t#{@trigger_word} #{hearer.to_s[5..-1]} " + parameters.join(" ") + "\n"
    end

    answer
  end

  private

  # takes an user_id and formats it in order to let Slack highlight the user
  def format_username(user_id)
    "<@#{user_id}>"
  end

  # takes an username (with Slack's format) and extracts the user_id
  def extract_user_id(username)
    username[2..-2]
  end

  def create_game_with_players(player1, player2, team1, team2, score1, score2)
    team_player1 = TeamPlayer.create(player: player1, team: team1, score: score1.to_i)
    team_player2 = TeamPlayer.create(player: player2, team: team2, score: score2.to_i)

    Game.create(team_player1: team_player1, team_player2: team_player2)
  end

  def ranking_for_scope(scope, n_weeks)
    n_weeks = n_weeks.to_i
    from = Date.today.beginning_of_week - (n_weeks - 1).week if n_weeks > 0

    ranking = scope.map { |player| { :rating => player.rating(from), :player => player} }
    ranking.sort_by! { |pr| -pr[:rating] }

    members = Slack.members
    return "Error: Couldn't fetch members list" if members.blank?

    rows = []

    ranking.each_with_index do |pr, index|

      name = pr[:player].member_name(members)

      rows << ["#{index+1}", name, "#{pr[:player].games_played(from)}", "#{pr[:player].won(from)}", "#{pr[:player].lost(from)}", "#{pr[:rating].to_i}"]
    end

    table = Terminal::Table.new :title => "League Table", :headings => ["Rank", "Speler", "Gespeeld", "Won", "Lost", "Rating"], :rows => rows

    "```#{table}```"
  end

  def filtered_ranking_for_scope(scope, games_played, n_weeks)
    n_weeks = n_weeks.to_i
    from = Date.today.beginning_of_week - (n_weeks - 1).week if n_weeks > 0

    ranking = scope.map { |player| { :rating => player.rating(from), :player => player} }
    ranking.sort_by! { |pr| -pr[:rating] }

    members = Slack.members
    return "Error: Couldn't fetch members list" if members.blank?

    rows = []

    ranking.each_with_index do |pr, index|
      if pr[:player].games_played(from) > (games_played -1)
        name = pr[:player].member_name(members)

        rows << ["#{index+1}", name, "#{pr[:player].games_played(from)}", "#{pr[:player].won(from)}", "#{pr[:player].lost(from)}", "#{pr[:rating].to_i}"]

      end
    end

    table = Terminal::Table.new :title => "League Table", :headings => ["Rank", "Speler", "Gespeeld", "Won", "Lost", "Rating"], :rows => rows

    "```#{table}```"
  end

  def r_for_scope(scope, n_weeks)
    n_weeks = n_weeks.to_i
    from = Date.today.beginning_of_week - (n_weeks - 1).week if n_weeks > 0

    ranking = scope.map { |player| { :rating => player.rating(from), :player => player} }
    ranking.sort_by! { |pr| -pr[:rating] }

    members = Slack.members
    return "Error: Couldn't fetch members list" if members.blank?

    rows = ranking.map.with_index do |pr, index|
      name = pr[:player].member_name(members)
      "#{index+1}. #{name} (#{pr[:rating].to_i})"
    end

    rows.join("\n")
  end

  # all hearers

  def hear_solo_ranking()
    ranking_for_scope(Player.player, 0)
  end

  def hear_team_ranking(games_played = 0)
    extract_user_id(player1)
    filtered_ranking_for_scope(PairPlayer.all, games_played.to_i, 0)
  end

  # def hear_filtered_ranking(games_played = 3, n_weeks = 0)
  #   filtered_ranking_for_scope(PairPlayer.all, games_played.to_i, n_weeks.to_i)
  # end

  # def hear_solo_r(n_weeks = 0)
  #   r_for_scope(Player.player, n_weeks)
  # end

  # def hear_team_r2(n_weeks = 0)
  #   r_for_scope(PairPlayer.all, n_weeks)
  # end

  def hear_2v2(winner1, winner2, score1, loser1, loser2, score2)
    _player1 = PairPlayer.find_or_create_by_users(extract_user_id(winner1), extract_user_id(winner2))
    _player2 = PairPlayer.find_or_create_by_users(extract_user_id(loser1), extract_user_id(loser2))

    _team1, _team2 = Team.find_by_name('test'), Team.find_by_name('test')

    return "Team #{team1} niet gekend" if _team1.nil?
    return "Team #{team2} niet gekend" if _team2.nil?

    create_game_with_players(_player1, _player2, _team1, _team2, score1, score2)

    "Match (#{winner1}, #{winner2}, #{score1}) - (#{loser1}, #{loser2}, #{score2}) Toegevoegd"
  end

  def hear_1v1(player1, score1, player2, score2)
    _player1 = Player.find_or_create_by(username: extract_user_id(player1))
    _player2 = Player.find_or_create_by(username: extract_user_id(player2))

    _team1, _team2 = Team.find_by_name('test'), Team.find_by_name('test')

    return "Team #{team1} niet gekend" if _team1.nil?
    return "Team #{team2} niet gekend" if _team2.nil?

    game = create_game_with_players(_player1, _player2, _team1, _team2, score1, score2)

    answer = "Match (#{player1}, #{score1}) - (#{player2}, #{score2}) toegevoegd"

    if game.drawn?
      answer += Taunt::MATCH_DRAWN.sample
    elsif [0, 1].sample == 0
      answer += Taunt::MATCH_WINNER.sample % format_username(game.winner.player.username)
    else
      answer += Taunt::MATCH_LOSER.sample % format_username(game.loser.player.username)
    end

    return answer
  end
  
  # def hear_challenge(player, time = "")
  #   other_user_id = extract_user_id(player)
  #   challenge_created = false

  #   if time.length > 0
  #     date = DateTime.parse(time) rescue nil
  #     return "Moi personnellement, j'ai pas compris l'heure moi tout seul" if date.nil?

  #     now = DateTime.now
  #     if (date.hour > now.hour) || (date.hour == now.hour && date.min > now.min)
  #       Challenge.find_or_create_by(player1_id: @user_id, player2_id: other_user_id, date: date)
  #       challenge_created = true
  #     end
  #   end

  #   player1 = Player.find_by(username: @user_id)
  #   player2 = Player.find_by(username: other_user_id)

  #   score = player1.compare(player2)

  #   answer = "#{format_username(@user_id)} daagt #{format_username(other_user_id)} uit tot KICKERDOME"
  #   answer += " op #{time}" if challenge_created

  #   if score < 0.0
  #     answer += Taunt::LOSER.sample % format_username(@user_id)
  #   elsif score > 0.0
  #     answer += Taunt::WINNER.sample % format_username(other_user_id)
  #   end

  #   answer
  # end

  # def hear_challenges
  #   challenges = Challenge.where("date >= ?", DateTime.now).order(:date)
  #   answer = "Uitdagingen:\n"
  #   answer += challenges.map { |challenge| "#{format_username(challenge.player1_id)} vs #{format_username(challenge.player2_id)} à #{challenge.date.strftime("%H:%M")}" }.join("\n")
  #   answer
  # end

  # def hear_stats(player1, player2)
    
  #   player = PairPlayer.find_by(extract_user_id(player1), extract_user_id(player2))

  #   return "Speler niet gevonden" if player.nil?

  #   answer = "Details voor #{format_username(player_id)} :\n"
  #   answer << "Zwaarste tegenstander (% overwinningen) : "
  #   answer << player.opponent_statistics.take(3).map { |opponent, score| "#{format_username(opponent)} : #{score}%" }.join(" - ")
  #   answer << "\n"
  #   answer << "Gemakkelijkste tegenstander (% overwinningen) : "
  #   answer << player.opponent_statistics.last(3).reverse.map { |opponent, score| "#{format_username(opponent)} : #{score}%" }.join(" - ")
  #   answer << "\n Globale statistieken : \n"

  #   percentage = lambda { |x| (100.0 * x / player.games_played.to_f).round(2) }
  #   win_rate = percentage.call(player.won.to_f)
  #   loss_rate = percentage.call(player.lost.to_f)
  #   draw_rate = percentage.call(player.drawn.to_f)

  #   answer << "Wins : #{win_rate}%, Losses : #{loss_rate}%, Draws : #{draw_rate}%\n"
  #   largest_victory = player.largest_victory

  #   answer
  # end

  def hear_undo
    minutes = 3

    game = Game.last

    return "Geen match van minder dan #{minutes} minuten geleden" if game.blank? or game.created_at < DateTime.now - minutes.minute

    game.destroy

    "Vorige match verwijderd. Leaderboard geüpdate"
  end

  def hear_ribery
    Ribery::QUOTES.sample
  end
end
