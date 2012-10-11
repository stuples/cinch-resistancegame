require 'cinch'
require 'yaml'

require File.expand_path(File.dirname(__FILE__)) + '/core'

module Cinch
  module Plugins

    CHANGELOG_FILE = File.expand_path(File.dirname(__FILE__)) + "/changelog.yml"

    class ResistanceGame
      include Cinch::Plugin

      def initialize(*args)
        super
        @game = Game.new
 
        @changelog     = self.load_changelog

        @mods          = config[:mods]
        @channel_name  = config[:channel]
        @settings_file = config[:settings]
      end


      match /join/i,             :method => :join
      match /leave/i,            :method => :leave
      match /start/i,            :method => :start_game
      match /team confirm$/i,    :method => :confirm_team
      match /confirm/i,          :method => :confirm_team
      match /team (.+)/i,        :method => :propose_team
      match /propose (.+)/i,     :method => :propose_team
      match /vote (.+)/i,        :method => :team_vote
      match /mission (.+)/i,     :method => :mission_vote
      match /assassinate (.+)/i, :method => :assassinate_player

      # helpers
      match /invite/i,           :method => :invite
      match /subscribe/i,        :method => :subscribe
      match /unsubscribe/i,      :method => :unsubscribe
      match /who$/i,             :method => :list_players
      match /missions/i,         :method => :missions_overview
      match /mission(\d)/i,      :method => :mission_summary
      match /score/i,            :method => :score
      match /info/i,             :method => :game_info
      match /status/i,           :method => :status
      match /help ?(.+)?/i,      :method => :help
      match /intro/i,            :method => :intro
      match /rules ?(.+)?/i,     :method => :rules
      match /settings$/i,        :method => :game_settings       
      match /settings (.+)/i,    :method => :set_game_settings
      match /changelog$/i,       :method => :changelog_dir
      match /changelog (\d+)/i,  :method => :changelog
   
      # mod only commands
      match /reset/i,              :method => :reset_game
      match /replace (.+?) (.+)/i, :method => :replace_user
      match /kick (.+)/i,          :method => :kick_user
      match /room (.+)/i,          :method => :room_mode
      match /whospies/i,           :method => :who_spies


      listen_to :join,          :method => :voice_if_in_game
      listen_to :leaving,       :method => :remove_if_not_started
      listen_to :op,            :method => :devoice_everyone_on_start

      #--------------------------------------------------------------------------------
      # Listeners
      #--------------------------------------------------------------------------------
      
      def voice_if_in_game(m)
        if @game.has_player?(m.user)
          Channel(@channel_name).voice(m.user)
        end
      end

      def remove_if_not_started(m, user)
        if @game.not_started?
          left = @game.remove_player(user)
          unless left.nil?
            Channel(@channel_name).send "#{user.nick} has left the game (#{@game.players.count}/#{Game::MAX_PLAYERS})"
          end
        end
      end

      def devoice_everyone_on_start(m, user)
        if user == bot
          self.devoice_channel
        end
      end

      #--------------------------------------------------------------------------------
      # Helpers
      #--------------------------------------------------------------------------------

      def help(m, page)
        if page == "mod" && self.is_mod?(m.user.nick)
          User(m.user).send "--- HELP PAGE MOD ---"
          User(m.user).send "!reset - completely resets the game to brand new"
          User(m.user).send "!replace nick1 nick1 - replaces a player in-game with a player out-of-game"
          User(m.user).send "!kick nick1 - removes a presumably unresponsive user from an unstarted game"
          User(m.user).send "!room (silent|vocal) - switches the channel from voice only users and back"
          User(m.user).send "!whospies - tells you the loyalties of the players in the game"
        else 
          case page
          when "2"
            User(m.user).send "--- HELP PAGE 2/3 ---"
            User(m.user).send "!info - shows spy count and team sizes for the game"
            User(m.user).send "!who - returns a player list of who is playing, in team leader order"
            User(m.user).send "!status - shows current status of the game, which phase of the round the game is in"
            User(m.user).send "!missions - shows all previous mission results"
            User(m.user).send "!mission1, !mission2, ... - shows a mission summary, including team voting history"
          when "3"
            User(m.user).send "--- HELP PAGE 3/3 ---"
            User(m.user).send "!rules (avalon|avroles) - provides rules for the game; when provided with an argument, provides specified rules"
            User(m.user).send "!subscribe - subscribe your current nick to receive PMs when someone calls !invite"
            User(m.user).send "!unsubscribe - remove your nick from the invitation list"
            User(m.user).send "!invite - invites #boardgames and subscribers to join the game"
            User(m.user).send "!changelog (#) - shows changelog for the bot, when provided a number it showed details"
          else
            User(m.user).send "--- HELP PAGE 1/3 ---"
            User(m.user).send "!join - joins the game"
            User(m.user).send "!leave - leaves the game"
            User(m.user).send "!start - starts the game"
            User(m.user).send "!team user1 user2 user3 - proposes a team with the specified users on it"
            User(m.user).send "!team confirm - puts the proposed team up for voting"
            User(m.user).send "!vote yes|no - vote for teams to make or not, yes or no"
            User(m.user).send "!mission pass|fail - vote for missions to pass or not, pass or fail"
            User(m.user).send "!help (#) - when provided a number, pulls up specified page"
          end
        end
      end

      def intro(m)
        User(m.user).send "Welcome to ResistanceBot. You can join a game if there's one getting started with the command \"!join\". For more commands, type \"!help\". If you don't know how to play, you can read a rules summary with \"!rules\". If already know how to play, great. But there's a few things you should know."
        User(m.user).send "** Please DO NOT private message with other players! This is against the spirit of the game."
        User(m.user).send "** When you vote for teams and missions (!vote and !mission), MAKE SURE you are PMing with ResistanceBot. You could accidentally reveal your loyalty and ruin the game otherwise."
      end

      def rules(m, section)
        case section
        when "avalon"
          User(m.user).send "The Resistance: Avalon is the same basic game as The Resistance, with slightly different terms to fit the theme. However, there are some special roles that some players may have.  By and large, the game is played the same way. However, the special characters change the amount of information that players start the game with."
          User(m.user).send "All Avalon games include Merlin and The Assassin. Other roles are optional (but have some dependencies)"
          User(m.user).send "Merlin is a member of the Resistance. His Wizardly abilities allow him to know who the Spies are.  While the Spies know who the Resistance are, they do not know which is Merlin. He can try to pass on information about the Spies, but he must be careful, lest the Spies identify him."
          User(m.user).send "The Assassin is a Spy. At the end of the game, if the Resistance have three successful Missions, then this is the Spies' last chance. The Assassin discusses with the other Spies who they think is Merlin. Once the Assassin has received guidance, he chooses a Resistance member to assassinate. If their victim really is Merlin, the Spies win. Otherwise, the Resistance win."
          User(m.user).send "For information about the optional roles, see !rules avroles"
        when "avroles"
          User(m.user).send "Percival is a member of the Resistance. He learns who Merlin is. He can use what Merlin says, and how he votes to garner information about the Spies. His principle aim, however, is to draw the attention of the Assassin away from Merlin. If the Resistance succeed in 3 Missions, if Percival has done his job right, the Assassin will fail to kill Merlin. However, watch out if Morgana is in the game."
          User(m.user).send "Mordred is a Spy. The other Spies know he is a Spy but do not know that he is Mordred. Merlin is unable to identify him, which means he doesn't have full information on all the Spies. (Merlin will see one fewer spies than are in the game)"
          User(m.user).send "Oberon is a Spy. However, he doesn't know who his fellow Spies are, and they do not know him, either.  (The other Spies will see one fewer Spies than are in the game). Merlin can identify Oberon as a Spy."
          User(m.user).send "Morgana is a Spy. Percival must be in the game to use Morgana. The other Spies know her as a Spy, as does Merlin, but none of them know her identity as Morgana.  However, Morgana's magic allows her to appear to Percival as if she were Merlin.  Percival will see two people claiming to be Merlin. He will know one is Resistance, the other a Spy. But he will not know for sure whose votes and conversation to trust."
        else
          User(m.user).send "GAME SETUP: When the game starts, ResistanceBot will PM you to tell you whether you are a Resistance or a Spy. If you are a Spy, it will also tell you who the other Spies are.  The number of Spies is dependent on the total number of players, but will always be strictly less than the number of Resistance members."
          User(m.user).send "HOW TO WIN: There will be up to 5 Missions. If you are a member of the Resistance, you and the rest of the Resistance will win if 3 Missions Pass.  If you are a Spy, you and the other Spies will win if 3 Missions Fail. The game is over as soon as one of those conditions is met. There is another win condition for the Spies, explained below."
          User(m.user).send "HOW TO PLAY: The Team Leader for the round will Propose a Team to go on the Mission. The Team size changes from Mission to Mission, and Team sizes for the game are dependent on the number of players. Everyone then Votes whether they want to approve the Proposed Team to go on the Mission or not. Votes are made in secret, but how players Voted will be publicly revealed after all Votes are in. This is a majority Vote, and a tie means the Proposed Team will not go on the Mission."
          User(m.user).send "If the Team is not approved, the next player becomes the Team Leader and proposes a new Team. If the Team proposal process fails 5 times in a row, the Spies win the game immediately; in practice, as there are always fewer Spies than Resistance, this means that everyone should vote to approve the fifth proposed Team since the last Mission."
          User(m.user).send "When a proposed Team has been approved, they go on the Mission. The Team members then decide if they want the Mission to Pass or Fail. Resistance can only vote for the Mission to Pass; it is against their objective to do otherwise. Spies can choose to Pass OR Fail. Maybe they want to gain trust; but maybe they want to score a Mission Fail for their team."
          User(m.user).send "After Mission decisions have been made, the results are shuffled and revealed. It takes only ONE Fail for the whole Mission to Fail. (Exception: in games with 7 or more players, because of the increased number of Spies, it requires TWO Fails for 4th Mission to Fail.) A Mission which does not Fail will Pass. After a Mission has been completed (Pass or Fail), the next player becomes the new Team Leader and proposes the next Team."
        end
      end

      def list_players(m)
        if @game.players.empty?
          m.reply "No one has joined the game yet."
        else
          m.reply @game.players.map{ |p| p == @game.hammer ? "#{p.user.nick}*" : p.user.nick }.join(' ')
        end
      end

      def missions_overview(m)
        round = @game.current_round.number
        (1..round).to_a.each do |number|
          prev_round = @game.get_prev_round(number)
          if ! prev_round.nil? && (prev_round.ended? || prev_round.in_mission_phase?)
            team = prev_round.team
            if prev_round.ended?
              if prev_round.mission_success?
                if prev_round.special_round?
                  fail_count = prev_round.mission_fails
                  fail_result = (fail_count == 1 ? "#{fail_count} FAIL" : "#{fail_count} FAILS")
                  mission_result = "PASSED (#{fail_result})"
                else
                  mission_result = "PASSED"
                end
              else
                mission_result = "FAILED (#{prev_round.mission_fails})"
              end
            else
              mission_result = "AWAY ON MISSION"
            end
            m.reply "MISSION #{number} - Leader: #{prev_round.team_leader.user.nick} - Team: #{team.players.map{ |p| p.user.nick }.join(', ')} - #{mission_result}"
          else
            #m.reply "A team hasn't been made for that round yet."
          end

        end
      end

      def mission_summary(m, round_number)
        number = round_number.to_i
        prev_round = @game.get_prev_round(number)
        if prev_round.nil?
          m.reply "That mission hasn't started yet."
        else
          teams = prev_round.teams
          m.reply "MISSION #{number}"
          teams.each_with_index do |team, i|
            went_team = team.team_makes? ? " - MISSION" : ""
            if team.team_votes.length == @game.players.length # this should probably be a method somewhere?
              m.reply "Team #{i+1} - Leader: #{team.team_leader.user.nick} - Team: #{team.players.map{ |p| p.user.nick }.join(', ')} - Votes: #{self.format_votes(team.team_votes)}#{went_team}"
            end
          end
          if prev_round.ended?
            m.reply "RESULT: #{prev_round.mission_success? ? "PASSED" : "FAILED (#{prev_round.mission_fails})"}"
          end
        end
      end

      def score(m)
        m.reply self.game_score
      end

      def game_info(m)
        if @game.started?
          m.reply self.get_game_info
        end
      end

      def status(m)
        m.reply @game.check_game_state
      end

      def changelog_dir(m)
        @changelog.each_with_index do |changelog, i|
          User(m.user).send "#{i+1} - #{changelog["date"]} - #{changelog["changes"].length} changes" 
        end
      end

      def changelog(m, page = 1)
        changelog_page = @changelog[page.to_i-1]
        User(m.user).send "Changes for #{changelog_page["date"]}:"
        changelog_page["changes"].each do |change|
          User(m.user).send "- #{change}"
        end
      end

      def invite(m)    
        if @game.accepting_players?
          if @game.invitation_sent?
            m.reply "An invitation has already been sent once for this game."
          else
            @game.mark_invitation_sent
            User("BG3PO").send "!invite_to_resistance_game"

            settings = load_settings || {}
            subscribers = settings["subscribers"]
            current_players = @game.players.map{ |p| p.user.nick }
            subscribers.each do |subscriber|
              unless current_players.include? subscriber
                User(subscriber).send "A game of Resistance is gathering in #playresistance ..."
              end
            end
          end
        end
      end

      def subscribe(m)
        settings = load_settings || {}
        subscribers = settings["subscribers"] || []
        if subscribers.include?(m.user.nick)
          User(m.user).send "You are already subscribed to the invitation list."
        else
          subscribers << m.user.nick 
          settings["subscribers"] = subscribers
          save_settings(settings)
          User(m.user).send "You've been subscribed to the invitation list."
        end
      end

      def unsubscribe(m)
        settings = load_settings || {}
        subscribers = settings["subscribers"] || []

        subscribers.delete_if{ |sub| sub == m.user.nick }

        settings["subscribers"] = subscribers
        save_settings(settings)
        User(m.user).send "You've been unsubscribed to the invitation list."
      end


      #--------------------------------------------------------------------------------
      # Main IRC Interface Methods
      #--------------------------------------------------------------------------------

      def join(m)
        if Channel(@channel_name).has_user?(m.user)
          if @game.accepting_players? 
            added = @game.add_player(m.user)
            unless added.nil?
              Channel(@channel_name).send "#{m.user.nick} has joined the game (#{@game.players.count}/#{Game::MAX_PLAYERS})"
              Channel(@channel_name).voice(m.user)
            end
          else
            if @game.started?
              Channel(@channel_name).send "#{m.user.nick}: Game has already started."
            elsif @game.at_max_players?
              Channel(@channel_name).send "#{m.user.nick}: Game is at max players."
            else
              Channel(@channel_name).send "#{m.user.nick}: You cannot join."
            end
          end
        else
          User(m.user).send "You need to be in #{@channel_name} to join the game."
        end
      end

      def leave(m)
        if @game.accepting_players?
          left = @game.remove_player(m.user)
          unless left.nil?
            Channel(@channel_name).send "#{m.user.nick} has left the game (#{@game.players.count}/#{Game::MAX_PLAYERS})"
            Channel(@channel_name).devoice(m.user)
          end
        else
          if @game.started?
            m.reply "Game is in progress.", true
          end
        end
      end

      def start_game(m)
        unless @game.started?
          if @game.at_min_players?
            if @game.has_player?(m.user)
              @game.start_game!

              self.pass_out_loyalties

              avalon_note = @game.avalon? ? " This is Resistance: Avalon, with #{@game.roles.map(&:capitalize).join(", ")}." : ""

              Channel(@channel_name).send "The game has started. #{self.get_game_info}#{avalon_note}"
              if @game.player_count >= 7
                Channel(@channel_name).send "This is a 7+ player game. Mission 4 will require TWO FAILS for the Spies."
              end
              Channel(@channel_name).send "Player order is: #{@game.players.map{ |p| p.user.nick }.join(' ')}"
              Channel(@channel_name).send "MISSION #{@game.current_round.number}. Team Leader: #{@game.team_leader.user.nick}. Please choose a team of #{@game.current_team_size} to go on the first mission."
              User(@game.team_leader.user).send "You are team leader. Please choose a team of #{@game.current_team_size} to go on first mission. \"!team#{team_example(@game.current_team_size)}\""
            else
              m.reply "You are not in the game.", true
            end
          else
            m.reply "Need at least #{Game::MIN_PLAYERS} to start a game.", true
          end
        end
      end

      def propose_team(m, players)
        if players != "confirm" 
          # make sure the providing user is team leader 
          if m.user == @game.team_leader.user
            players = players.split(/[\s,]+/).map{ |p| @game.find_player(User(p)) || p }.uniq

            non_players = players.dup.delete_if{ |p| p.is_a? Player }
            actual_players = players.dup.keep_if{ |p| p.is_a? Player }

            # make sure the names are valid
            if non_players.count > 0
              User(@game.team_leader.user).send "You have entered invalid name(s): #{non_players.join(', ')}"
            # then check sizes
            elsif players.count < @game.current_team_size
              User(@game.team_leader.user).send "You don't have enough operatives on the team. You need #{@game.current_team_size}."
            elsif players.count > @game.current_team_size
              User(@game.team_leader.user).send "You have too many operatives on the team. You need #{@game.current_team_size}."
            # then we are okay
            else
              @game.make_team(actual_players)
              if @game.team_selected? # another safe check just because
                proposed_team = @game.current_round.team.players.map(&:user).join(', ')
                Channel(@channel_name).send "#{m.user.nick} is proposing the team: #{proposed_team}."
              end
            end
          else
            User(m.user).send "You are not the team leader."
          end
        end
      end

      def confirm_team(m)
        # make sure the providing user is team leader 
        if m.user == @game.team_leader.user
          if @game.team_selected? 
            @game.current_round.call_for_votes
            proposed_team = @game.current_round.team.players.map(&:user).join(', ')
            Channel(@channel_name).send "The proposed team: #{proposed_team}. Time to vote!"
            @game.players.each do |p|
              hammer_warning = (@game.current_round.hammer_team?) ? " This is your LAST chance at voting a team for this mission; if this team is not accepted, the Resistance loses." : ""
              vote_prompt = "Time to vote! Vote whether or not you want the team (#{proposed_team}) to go on the mission or not. \"!vote yes\" or \"!vote no\".#{hammer_warning}"
              User(p.user).send vote_prompt
            end
          else 
            User(@game.team_leader.user).send "You don't have enough members on the team. You need #{@game.current_team_size} operatives."
          end 
        else
          User(m.user).send "You are not the team leader."
        end
      end

      def team_vote(m, vote)
        if @game.current_round.in_vote_phase? && @game.has_player?(m.user)
          vote.downcase!
          if ['yes', 'no'].include?(vote)
            @game.vote_for_team(m.user, vote)
            User(m.user).send "You voted '#{vote}' for the team."
            if @game.all_team_votes_in?
              self.process_team_votes
            end
          else 
            User(player.user).send "You must vote 'yes' or 'no'."
          end
        end
      end

      def mission_vote(m, vote)
        if @game.current_round.in_mission_phase?
          player = @game.find_player(m.user)
          if player.spy?
            valid_options = ['pass', 'fail']
          else
            valid_options = ['pass']
          end

          if @game.current_round.team.players.include?(player)
            vote.downcase!
            if valid_options.include?(vote)
              @game.vote_for_mission(m.user, vote)
              User(m.user).send "You voted for the mission to '#{vote}'."
              if @game.all_mission_votes_in?
                self.process_mission_votes
              end
            else 
              User(player.user).send "You must vote #{valid_options.join(" or ")}."
            end
          else
            User(player.user).send "You are not on this mission."
          end
        end
      end

      def assassinate_player(m, target)
        if @game.is_over?
          if @game.find_player_by_role(:assassin).user == m.user
            killed = @game.find_player(target)
            if killed.nil?
              User(m.user).send "\"#{target}\" is an invalid target."
            else
              if killed.role?(:merlin)
                Channel(@channel_name).send "The assassin kills #{killed.user.nick}. The spies have killed Merlin! Spies win the game!"
              else 
                Channel(@channel_name).send "The assassin kills #{killed.user.nick}. The spies have NOT killed Merlin. Resistance wins!"
              end
              self.start_new_game
            end

          else
            User(m.user).send "You are not the assassin."
          end
        end
      end


      #--------------------------------------------------------------------------------
      # Game interaction methods
      #--------------------------------------------------------------------------------

      def team_example(size)
        size.times.map { |i| " name#{i+1}" }.join("")
      end
      
      def pass_out_loyalties
        @game.players.each do |p|
          reply = self.tell_loyalty_to(p)
        end
      end

      def tell_loyalty_to(player)
        if @game.avalon?
          spies = @game.spies

          # if player is a spy, they can see other spies, but not oberon if he's in play
          if player.spy?
            other_spies = spies.reject{ |s| s.role?(:oberon) || s == player }.map{ |s| s.user.nick }
          end
        
          # here we goooo...
          if player.role?(:merlin)
            # sees spies minus mordred
            spies_minus_mordred = spies.reject{ |s| s.role?(:mordred) }.map{ |s| s.user.nick }
            loyalty_msg = "You are MERLIN (resistance). Don't let the spies learn who you are. The spies are: #{spies_minus_mordred.join(', ')}. "
          elsif player.role?(:assassin)
            loyalty_msg = "You are THE ASSASSIN (spy). Try to figure out who Merlin is. The other spies are: #{other_spies.join(', ')}."
          elsif player.role?(:percival)
            # sees merlin (and morgana)
            merlin = @game.find_player_by_role(:merlin)
            morgana = @game.find_player_by_role(:morgana)
            revealed_to_percival = ( morgana.nil? ? [merlin] : [merlin, morgana].shuffle )
            revealed_to_percival_names = revealed_to_percival.map!{ |s| s.user.nick }
            loyalty_msg = "You are PERCIVAL (resistance). Help protect Merlin's identity. Merlin is: #{revealed_to_percival_names.join(', ')}."
          elsif player.role?(:mordred)
            loyalty_msg = "You are MORDRED (spy). You didn't reveal yourself to Merlin. The other spies are: #{other_spies.join(', ')}."
          elsif player.role?(:oberon)
            loyalty_msg = "You are OBERON (spy). You are a bad guy, but you don't reveal to them and they don't reveal to you."
          elsif player.role?(:morgana)
            loyalty_msg = "You are MORGANA (spy). You revealed yourself as Merlin to Percival. The other spies are: #{other_spies.join(', ')}."
          elsif player.role?(:spy)
            loyalty_msg = "You are A SPY. The other spies are: #{other_spies.join(', ')}."
          elsif player.role?(:resistance)
            loyalty_msg = "You are a member of the RESISTANCE."
          else
            loyalty_msg = "I don't know what you are. Something's gone wrong."
          end
        else
          if player.spy?
            other_spies = @game.spies.reject{ |s| s == player }.map{ |s| s.user.nick }
            loyalty_msg = "You are A SPY! The other spies are: #{other_spies.join(', ')}."
          else
            loyalty_msg = "You are a member of the RESISTANCE."
          end
        end
        User(player.user).send loyalty_msg
      end

      def get_game_info
        team_sizes = @game.team_sizes.values
        if @game.player_count >= 7
          team_sizes[3] = team_sizes.at(3).to_s + "*"
        end
        "There are #{@game.player_count} players, with #{@game.spies.count} spies. Team sizes will be: #{team_sizes.join(", ")}"
      end

      def start_new_round
        @game.start_new_round
        two_fail_warning = (@game.current_round.special_round?) ? " This mission requires TWO FAILS for the spies." : ""
        Channel(@channel_name).send "MISSION #{@game.current_round.number}. Team Leader: #{@game.team_leader.user.nick}. Please choose a team of #{@game.current_team_size} to go on the mission.#{two_fail_warning}"
        User(@game.team_leader.user).send "You are team leader. Please choose a team of #{@game.current_team_size} to go on the mission. \"!team#{team_example(@game.current_team_size)}\""
      end

      def process_team_votes
        # reveal the votes
        Channel(@channel_name).send "The votes are in for the team: #{@game.current_round.team.players.map(&:user).join(', ')}"
        Channel(@channel_name).send self.format_votes(@game.current_round.team.team_votes)

        # determine if team makes
        if @game.current_round.team_makes?
          @game.go_on_mission
          Channel(@channel_name).send "This team is going on the mission!"
          @game.current_round.team.players.each do |p|
            if p.spy?
              mission_prompt = 'Mission time! Since you are a spy, you have the option to PASS or FAIL the mission. "!mission pass" or "!mission fail"'
            else
              mission_prompt = 'Mission time! Since you are resistance, you can only choose to PASS the mission. "!mission pass"'
            end
            User(p.user).send mission_prompt
          end
        else
          @game.try_making_team_again
          Channel(@channel_name).send "This team is NOT going on the mission. Fail count: #{@game.current_round.fail_count}"
          if @game.current_round.too_many_fails?
            self.do_end_game
          else
            hammer_warning = (@game.current_round.hammer_team?) ? " This is your LAST chance at making a team for this mission; if this team is not accepted, the Resistance loses." : ""
            Channel(@channel_name).send "MISSION #{@game.current_round.number}. #{@game.team_leader.user.nick} is the new team leader. Please choose a team of #{@game.current_team_size} to go on the this mission.#{hammer_warning}"
            User(@game.team_leader.user).send "You are the new team leader. Please choose a team of #{@game.current_team_size} to go on the mission. \"!team#{team_example(@game.current_team_size)}\""
            @game.current_round.back_to_team_making
          end

        end
      end

      def format_votes(team_votes)
        yes_votes = team_votes.select{ |p, v| v == 'yes' }.map {|p, v| p.user.nick }.shuffle
        no_votes  = team_votes.select{ |p, v| v == 'no'  }.map {|p, v| p.user.nick }.shuffle
        if no_votes.empty?
          votes = "YES - #{yes_votes.join(", ")}"
        elsif yes_votes.empty?
          votes = "NO - #{no_votes.join(", ")}"
        else
          votes = "YES - #{yes_votes.join(", ")} | NO - #{no_votes.join(", ")}"
        end

        votes
      end

      def process_mission_votes
        # reveal the results
        Channel(@channel_name).send "The team is back from the mission..."
        @game.current_round.mission_votes.values.sort.reverse.each do |vote|
          sleep 3
          Channel(@channel_name).send vote.upcase
        end
        sleep 2
        # determine if mission passes
        if @game.current_round.mission_success?
          Channel(@channel_name).send "... the mission passes!"
        else
          Channel(@channel_name).send "... the mission fails!"
        end
        self.check_game_state
      end

      def check_game_state
        Channel(@channel_name).send self.game_score
        if @game.is_over?
          self.do_end_game
        else
          self.start_new_round
        end
      end

      def do_end_game
        spies = @game.spies.map{|s| s.user.nick}.join(", ")
        if @game.spies_win?
          Channel(@channel_name).send "Game is over! The spies have won!"
          Channel(@channel_name).send "The spies were: #{spies}"
          self.start_new_game
        else
          if @game.avalon?
            assassin = @game.find_player_by_role(:assassin)
            Channel(@channel_name).send "The resistance successfully completed the missions, but the spies still have a chance."
            Channel(@channel_name).send "The spies are: #{spies}. The assassin is: #{assassin.user.nick}. Choose a resistance member to assassinate."
            User(assassin.user).send "You are the assassin, and it's time to assassinate one of the resistance. \"!assassinate name\""
          else
            Channel(@channel_name).send "Game is over! The resistance wins!"
            Channel(@channel_name).send "The spies were: #{spies}"
            self.start_new_game
          end
        end
      end

      def start_new_game
        Channel(@channel_name).moderated = false
        @game.players.each do |p|
          Channel(@channel_name).devoice(p.user)
        end
        @game.save_game
        @game = Game.new
      end


      def game_score
        @game.mission_results.map{ |mr| mr ? "O" : "X" }.join(" ")
      end

      def devoice_channel
        Channel(@channel_name).voiced.each do |user|
          Channel(@channel_name).devoice(user)
        end
      end

      #--------------------------------------------------------------------------------
      # Mod commands
      #--------------------------------------------------------------------------------

      def is_mod?(nick)
        # make sure that the nick is in the mod list and the user in authenticated        
        @mods.include?(nick) && User(nick).authed?
      end

      def reset_game(m)
        if self.is_mod? m.user.nick
          @game = Game.new
          self.devoice_channel
          Channel(@channel_name).send "The game has been reset."
        end
      end

      def kick_user(m, nick)
        if self.is_mod? m.user.nick
          if @game.not_started?
            user = User(nick)
            left = @game.remove_player(user)
            unless left.nil?
              Channel(@channel_name).send "#{user.nick} has left the game (#{@game.players.count}/#{Game::MAX_PLAYERS})"
              Channel(@channel_name).devoice(user)
            end
          else
            User(m.user).send "You can't kick someone while a game is in progress."
          end
        end
      end

      def replace_user(m, nick1, nick2)
        if self.is_mod? m.user.nick
          # find irc users based on nick
          user1 = User(nick1)
          user2 = User(nick2)
          
          # replace the users for the players
          player = @game.find_player(user1)
          player.user = user2

          # devoice/voice the players
          Channel(@channel_name).devoice(user1)
          Channel(@channel_name).voice(user2)

          # inform channel
          Channel(@channel_name).send "#{user1.nick} has been replaced with #{user2.nick}"

          # tell loyalty to new player
          self.tell_loyalty_to(player)
        end
      end

      def room_mode(m, mode)
        if self.is_mod? m.user.nick
          case mode
          when "silent"
            Channel(@channel_name).moderated = true
          when "vocal"
            Channel(@channel_name).moderated = false
          end
        end
      end

      def who_spies(m)
        if self.is_mod? m.user.nick
          if @game.started?
            if @game.has_player?(m.user)
              User(m.user).send "You are in the game, goof!"
            else  
              spies = @game.spies.map{ |s| s.user.nick }
              User(m.user).send "Okay! The spies are: #{spies.join(", ")}."  
            end
          else
            User(m.user).send "There is no game going on."
          end
        end
      end

      #--------------------------------------------------------------------------------
      # Game Settings
      #--------------------------------------------------------------------------------

      def game_settings(m)
        if @game.type == :base
          m.reply "Game settings: Base."
        elsif @game.type == :avalon
          m.reply "Game settings: Avalon. Using roles: #{@game.roles.map(&:capitalize).join(", ")}."
        end
      end

      def set_game_settings(m, options)
        unless @game.started?
          options = options.split(" ")
          game_type = options.shift
          if game_type.downcase == "avalon"
            valid_options = ["percival", "mordred", "oberon", "morgana"]
            options.keep_if{ |opt| valid_options.include?(opt.downcase) }
            roles = (["merlin", "assassin"] + options)
            @game.change_type "avalon", roles.map(&:to_sym)
            Channel(@channel_name).send "The game has been changed to Avalon. Using roles: #{roles.map(&:capitalize).join(", ")}."
          else
            @game.change_type "base"
            Channel(@channel_name).send "The game has been changed to base."
          end
        end
      end

      #--------------------------------------------------------------------------------
      # Settings
      #--------------------------------------------------------------------------------
      
      def save_settings(settings)
        output = File.new(@settings_file, 'w')
        output.puts YAML.dump(settings)
        output.close
      end

      def load_settings
        output = File.new(@settings_file, 'r')
        settings = YAML.load(output.read)
        output.close

        settings
      end

      def load_changelog
        output = File.new(CHANGELOG_FILE, 'r')
        changelog = YAML.load(output.read)
        output.close

        changelog
      end
      

    end
    
  end
end
