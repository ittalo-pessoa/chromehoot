module Teacher
  class QuizzesController < BaseController
    before_action :set_quiz, only: %i[show edit update destroy duplicate]

    def index
      @quizzes = current_user.quizzes.where(archived_at: nil).order(created_at: :desc)
      @games = current_user.game_sessions.order(created_at: :desc).limit(10)
      @answers = Answer.joins(:round).where(rounds: { game_session_id: current_user.game_sessions.select(:id) })
    end

    def show; end
    def new
      @quiz = current_user.quizzes.new
    end
    def edit; end
    def create
      @quiz = current_user.quizzes.new(quiz_params)
      if @quiz.save
        redirect_to teacher_quiz_path(@quiz), notice: "Quiz criado. Adicione as questões."
      else
        render :new, status: :unprocessable_entity
      end
    end
    def update
      if @quiz.update(quiz_params)
        redirect_to teacher_quiz_path(@quiz), notice: "Quiz atualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end
    def destroy
      @quiz.update!(archived_at: Time.current)
      redirect_to teacher_quizzes_path, notice: "Quiz arquivado. O histórico foi preservado.", status: :see_other
    end
    def duplicate
      copy = nil
      @quiz.with_lock do
        copy = current_user.quizzes.create!(title: "#{@quiz.title.first(150)} (cópia)", subject: @quiz.subject, description: @quiz.description)
        copy.background_music.attach(@quiz.background_music.blob) if @quiz.background_music.attached?
        @quiz.questions.includes(:choices).each do |question|
          q = copy.questions.create!(statement: question.statement, position: question.position, time_limit_seconds: question.time_limit_seconds,
            choices_attributes: question.choices.map { |c| c.attributes.slice("text", "correct", "position") })
          q.image.attach(question.image.blob) if question.image.attached?
        end
      end
      redirect_to teacher_quiz_path(copy), notice: "Quiz duplicado."
    end

    private
    def set_quiz
      @quiz = current_user.quizzes.find(params[:id])
    end
    def quiz_params
      params.require(:quiz).permit(:title, :description, :subject, :background_music)
    end
  end
end
