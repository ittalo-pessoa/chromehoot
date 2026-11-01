class PlayController < ApplicationController
  before_action :authenticate_participant, except: :join
  before_action { response.headers["Cache-Control"] = "no-store" }
  def join
    token = cookies.signed[:participant_token]
    previous = Participant.includes(:game_session).find_by(credential_digest: Digest::SHA256.hexdigest(token)) if token.present?
    if previous && previous.game_session.join_code == params[:code].to_s.strip
      raise GameError, "Esta sala já foi encerrada. Peça ao professor o código de uma nova partida." if previous.game_session.terminal?
      raise GameError, "Sua participação nesta sala foi removida pelo professor." if previous.removed_at?
      return redirect_to play_path, notice: "Sua participação foi recuperada."
    end
    AccessAttempt.check!("join:#{browser_key}", limit: 30)
    participant, token = ParticipantsJoin.call(code: params[:code], nickname: params[:nickname])
    cookies.signed[:participant_token] = { value: token, httponly: true, same_site: :lax, secure: request.ssl?, expires: 2.days.from_now }
    redirect_to play_path, notice: "Você entrou como #{participant.nickname}."
  end
  def show; end
  def state
    render json: GameState.call(@participant.game_session, participant: @participant)
  end
  def answer
    Answers::Submit.call(@participant, round_id: params[:round_id], choice_id: params[:choice_id])
    render json: { accepted: true }
  end
  def leave
    cookies.delete(:participant_token)
    redirect_to root_path, status: :see_other
  end
  private
  def authenticate_participant
    token = cookies.signed[:participant_token]
    @participant = Participant.find_by(credential_digest: Digest::SHA256.hexdigest(token)) if token.present?
    return if @participant
    if request.format.json?
      render json: { error: "Entre na sala novamente." }, status: :unauthorized
    else
      redirect_to root_path, alert: "Entre na sala para participar."
    end
  end
end
