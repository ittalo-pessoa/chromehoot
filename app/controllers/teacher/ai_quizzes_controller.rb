module Teacher
  class AiQuizzesController < BaseController
    before_action :set_draft, only: %i[show state import destroy]

    def new
      @draft = current_user.ai_quiz_drafts.new(question_count: 3, difficulty: "easy")
      load_history
    end

    def create
      @draft = current_user.ai_quiz_drafts.new(draft_params)
      AccessAttempt.check!("ai:#{current_user.id}", limit: 8)
      current_user.with_lock do
        raise GameError, "Você já tem uma geração em andamento. Aguarde ou abra o pedido anterior." if current_user.ai_quiz_drafts.where(status: %w[queued processing]).exists?
        @draft.save!
      end
      redirect_to teacher_ai_quiz_path(@draft), notice: "Pedido enviado para a IA."
    rescue ActiveRecord::RecordInvalid => error
      @draft = error.record
      load_history
      render :new, status: :unprocessable_entity
    rescue GameError => error
      @draft.errors.add(:base, error.message)
      load_history
      render :new, status: :unprocessable_entity
    end

    def show
      @review = @draft.content
    end

    def state
      render json: { status: @draft.status, error_message: @draft.error_message }
    end

    def import
      raise GameError, "Confirme que revisou enunciados, alternativas e gabarito." unless params[:reviewed] == "1"
      data = params.require(:content).permit(:title, :description, questions: [ :statement, :time_limit_seconds, :correct_index, { choices: [] } ]).to_h
      @review = data
      quiz = AiQuizzes::Import.call(@draft, data)
      redirect_to teacher_quiz_path(quiz), notice: "Quiz revisado e salvo. Você já pode editar ou criar uma sala."
    rescue GameError, ActiveRecord::RecordInvalid => error
      @review ||= @draft.content
      flash.now[:alert] = error.is_a?(GameError) ? error.message : error.record.errors.full_messages.join(", ")
      render :show, status: :unprocessable_entity
    end

    def destroy
      @draft.with_lock { @draft.destroy! }
      redirect_to new_teacher_ai_quiz_path, notice: "Pedido de IA excluído. Um quiz já salvo a partir dele permanece nos seus quizzes.", status: :see_other
    end

    private

    def set_draft
      @draft = current_user.ai_quiz_drafts.find(params[:id])
    end

    def draft_params
      params.require(:ai_quiz_draft).permit(:topic, :subject, :grade_level, :difficulty, :question_count)
    end

    def load_history
      @drafts = current_user.ai_quiz_drafts.order(created_at: :desc).limit(10)
    end
  end
end
