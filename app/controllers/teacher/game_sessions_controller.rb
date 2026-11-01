module Teacher
  class GameSessionsController < BaseController
    before_action :set_game, except: %i[index create]
    def index
      @games = current_user.game_sessions.includes(:quiz).order(created_at: :desc)
    end
    def create
      quiz = current_user.quizzes.find(params[:quiz_id])
      game = GameSessions::Create.call(quiz)
      redirect_to teacher_game_session_path(game)
    end
    def show; end
    def projector
      render :show
    end
    def state
      render json: GameState.call(@game, teacher: action_name != "projector")
    end
    def command
      GameSessions::Transition.call(@game, params[:command], round_id: params[:round_id])
      redirect_to teacher_game_session_path(@game), status: :see_other
    end
    def remove_participant
      @game.with_lock { @game.participants.find(params[:participant_id]).update!(removed_at: Time.current) }
      redirect_to teacher_game_session_path(@game), notice: "Participante removido.", status: :see_other
    end
    def report
      @ranking = Rankings::Build.call(@game)
      @rounds = @game.rounds.where.not(opened_at: nil).includes(:session_question)
      respond_to do |format|
        format.html
        format.csv { send_data Reports::ExportCsv.call(@game), filename: "chromehoot-#{@game.join_code}.csv", type: "text/csv; charset=utf-8" }
      end
    end
    private
    def set_game
      @game = current_user.game_sessions.find(params[:id])
    end
  end
end
